# frozen_string_literal: true

require "minitest/autorun"
require_relative "../speech_normalizer"

class SpeechNormalizerTest < Minitest::Test
  def test_cyrillic_stress_and_brackets_preserve_words
    source = "Маита́ке и [неясное название], бо́льшая доза."
    result = SpeechNormalizer.normalize(source)
    assert_equal "Маитаке и (неясное название), большая доза.", result.text
    assert_includes source, "\u0301"
    assert result.audit[:replacements].any? { |entry| entry.to_s.include?("stress") }
  end

  def normalize(text, replacements: {})
    SpeechNormalizer.normalize(text, replacements: replacements)
  end

  def test_user_replacements_are_first_case_insensitive_and_longest_match
    source = "CRATAEGUS monogyna и Crataegus, Instagram."
    replacements = {
      "crataegus" => "боярышник",
      "Crataegus monogyna" => "боярышник однопестичный",
      "instagram" => "социальная сеть"
    }

    result = normalize(source, replacements: replacements)

    assert_equal "боярышник однопестичный и боярышник, социальная сеть.", result.text
    assert_equal source, "CRATAEGUS monogyna и Crataegus, Instagram."
    assert_equal [
      { kind: "user", source: "CRATAEGUS monogyna", replacement: "боярышник однопестичный" },
      { kind: "user", source: "Crataegus", replacement: "боярышник" },
      { kind: "user", source: "Instagram", replacement: "социальная сеть" }
    ], result.audit[:replacements]
    assert_empty result.audit[:foreign_tokens]
  end

  def test_integers_signs_leading_zeroes_and_unicode_decimal_digits
    result = normalize("0, 1, 2, 11, 21, 100, 1000, -5, +7, 007 и ١٢.")

    assert_equal "ноль, один, два, одиннадцать, двадцать один, сто, одна тысяча, минус пять, плюс семь, ноль ноль семь и двенадцать.", result.text
    refute_match(/[\p{N}\p{Latin}]/, result.text)
    assert_equal %w[unicode_digit unicode_digit integer integer integer integer integer integer integer integer integer integer integer],
                 result.audit[:replacements].map { |entry| entry[:kind] }
  end

  def test_decimals_percentages_fractions_ranges_and_celsius
    result = normalize("0,5; 1,25; 0,5%; 5%; 1/2; 3/4; 5–10 дней; 37,5 °C; 80 °C.")

    assert_equal "ноль целых пять десятых; одна целая двадцать пять сотых; ноль целых пять десятых процента; " \
                 "пять процентов; одна вторая; три четвёртых; от пяти до десяти дней; " \
                 "тридцать семь целых пять десятых градуса Цельсия; восемьдесят градусов Цельсия.", result.text
  end

  def test_synthetic_speech_values_keep_every_dose_fraction_range_date_percent_and_unit
    source = +"5 мг/кг; 1/2 таблетки; 3–7 дней; 01.09.2026; 12,5%; 250 мкг и 2 ml."
    original = source.b.dup
    result = normalize(source)

    assert_equal "пять миллиграммов на килограмм; одна вторая таблетки; от трёх до семи дней; " \
                 "первое сентября две тысячи двадцать шестого года; двенадцать целых пять десятых процента; " \
                 "двести пятьдесят микрограммов и два миллилитра.", result.text
    assert_equal original, source.b
    %w[пять семи двенадцать двести пятьдесят].each do |spoken_value|
      assert_includes result.text, spoken_value
    end
  end

  def test_common_units_have_russian_number_and_noun_agreement
    result = normalize("1 мг, 2 ml, 5 g, 21 кг, 1 mcg, 2 л, 1 капля, 2 drops, 5 таблеток, 3 раза, 1 мин, 2 hours.")

    assert_equal "один миллиграмм, два миллилитра, пять граммов, двадцать один килограмм, один микрограмм, " \
                 "два литра, одна капля, две капли, пять таблеток, три раза, одна минута, два часа.", result.text
  end

  def test_unit_range_and_decimal_quantity_are_replaced_as_whole_expressions
    result = normalize("Принимать 1–2 таблетки, 0,25 мл и сделать перерыв на 2 недели.")

    assert_equal "Принимать от одной до двух таблеток, ноль целых двадцать пять сотых миллилитра и сделать перерыв на две недели.", result.text
    assert_equal %w[unit_range unit unit], result.audit[:replacements].map { |entry| entry[:kind] }
  end

  def test_years_dates_and_times_use_contextual_forms
    result = normalize("С 2008 года, в 2026 году. Дата: 01.09.2026; 15 октября. В 8:30 и 21:15:05.")

    assert_equal "С две тысячи восьмого года, в две тысячи двадцать шестом году. " \
                 "Дата: первое сентября две тысячи двадцать шестого года; пятнадцатого октября. " \
                 "В восемь часов тридцать минут и двадцать один час пятнадцать минут пять секунд.", result.text
  end

  def test_number_sign_and_phone_number
    result = normalize("Рецепт № 5. Телефон: +49 30 12345678.")

    assert_equal "Рецепт номер пять. Телефон: плюс четыре девять, три ноль, один два три четыре пять шесть семь восемь.", result.text
    assert_equal %w[number_sign phone], result.audit[:replacements].map { |entry| entry[:kind] }.sort
  end

  def test_medical_mixed_identifiers_are_never_dropped
    result = normalize("B12, CYP3A4, CYP2D6, COVID-19, GABA, DNA, RNA, pH, H1N1 и омега-3.")

    assert_equal "витамин бэ двенадцать, цитохром пи три эй четыре, цитохром пи два ди шесть, " \
                 "ковид девятнадцать, гамма-аминомасляная кислота, дэ эн ка, эр эн ка, пэ аш, " \
                 "эйч один эн один и омега три.", result.text
    refute_match(/[\p{N}\p{Latin}]/, result.text)
  end

  def test_existing_word_vitamin_is_not_duplicated_before_b12
    result = normalize("Витамин B12 и B6.")
    assert_equal "Витамин бэ двенадцать и витамин бэ шесть.", result.text
  end

  def test_known_botanical_and_lecture_terms_have_stable_pronunciation
    result = normalize("Hypericum perforatum, Echinacea purpurea, Withania somnifera, Ginkgo biloba и Crataegus.")

    assert_equal "Гиперикум перфоратум, Эхинацея пурпуреа, Витания сомнифера, Гинкго билоба и Кратэгус.", result.text
    assert_equal Array.new(5, "known"), result.audit[:foreign_tokens].map { |entry| entry[:strategy] }
  end

  def test_botanical_latin_and_unlisted_term_keep_all_words_without_dictionary_guessing
    source = +"Achillea millefolium, Crataegus monogyna, Salvia officinalis."
    original = source.b.dup
    result = normalize(source)

    assert_equal "Ахиллеа миллефолиум, Кратэгус моногина, Салвиа оффициналис.", result.text
    assert_equal original, source.b
    assert_equal %w[known transliteration transliteration transliteration transliteration],
                 result.audit[:foreign_tokens].map { |entry| entry[:strategy] }
  end

  def test_known_english_phrases_are_translated_before_single_words
    result = normalize("standardized extract, food supplement, daily dose; sleep, stress, tincture, dosage.")

    assert_equal "стандартизированный экстракт, пищевая добавка, суточная доза; слип, стресс, тинктура, дозировка.", result.text
    assert_equal 7, result.audit[:foreign_tokens].length
  end

  def test_unknown_latin_and_german_words_are_conservatively_transliterated
    result = normalize("Bergamotte, Schlaf, Öl, ätherisch и test.")

    assert_equal "Бергамотте, Шлаф, Ёл, этериш и тест.", result.text
    assert_equal Array.new(5, "transliteration"), result.audit[:foreign_tokens].map { |entry| entry[:strategy] }
  end

  def test_audit_separates_replacements_from_foreign_tokens
    result = normalize("5 mg Crataegus XYZ")

    assert_equal "пять миллиграммов Кратэгус икс уай зед", result.text
    assert_equal [
      { kind: "unit", source: "5 mg", replacement: "пять миллиграммов" }
    ], result.audit[:replacements]
    assert_equal [
      { source: "Crataegus", replacement: "Кратэгус", strategy: "known" },
      { source: "XYZ", replacement: "икс уай зед", strategy: "transliteration" }
    ], result.audit[:foreign_tokens]
  end

  def test_display_text_is_not_mutated
    source = +"Доза 5 мг и Crataegus."
    original_object_id = source.object_id

    result = normalize(source)

    assert_equal "Доза 5 мг и Crataegus.", source
    assert_equal original_object_id, source.object_id
    assert_equal "Доза пять миллиграммов и Кратэгус.", result.text
  end

  def test_safe_fragment_cleanup_is_narrow_and_preserves_punctuation_and_brackets
    source = +"[Текст},{продолжается], неизвестное Crataegus?"
    bytes_before = source.b.dup
    result = normalize(source)

    assert_equal "(Текст, продолжается), неизвестное Кратэгус?", result.text
    assert_equal bytes_before, source.b
  end

  def test_mixed_script_and_placeholder_diagnostics_include_unicode_codepoints
    source = +"Название Crаtaegus"
    bytes_before = source.b.dup
    error = assert_raises(SpeechNormalizer::UnsupportedScriptError) { normalize(source) }
    assert_includes error.message, "U+0430"
    assert_equal bytes_before, source.b

    placeholder = assert_raises(SpeechNormalizer::Error) { normalize("Доза {{amount}}.") }
    assert_includes placeholder.message, "U+007B"
    assert_includes placeholder.message, "U+007D"
  end

  def test_user_replacement_can_resolve_an_otherwise_unsupported_script
    result = normalize("Препарат 茶.", replacements: { "茶" => "чай" })

    assert_equal "Препарат чай.", result.text
  end

  def test_unsupported_script_is_a_hard_error
    error = assert_raises(SpeechNormalizer::UnsupportedScriptError) { normalize("Препарат 茶 и δ.") }

    assert_equal "Неподдерживаемая письменность: 茶, δ", error.message
  end

  def test_unresolved_unicode_number_symbol_is_a_hard_error
    error = assert_raises(SpeechNormalizer::UnresolvedNumberError) { normalize("Глава Ⅻ.") }

    assert_includes error.message, "Ⅻ"
    assert_includes error.message, "U+216B"
  end

  def test_invalid_date_and_time_are_not_silently_reinterpreted
    assert_raises(SpeechNormalizer::Error) { normalize("Дата 31.02.2026.") }
    assert_raises(SpeechNormalizer::Error) { normalize("Время 25:61.") }
  end

  def test_ambiguous_german_thousands_and_scientific_notation_are_hard_errors
    assert_raises(SpeechNormalizer::Error) { normalize("Доза 5.000 мг.") }
    assert_raises(SpeechNormalizer::Error) { normalize("Доза 1,000 mg.") }
    assert_raises(SpeechNormalizer::Error) { normalize("Концентрация 1e-3 M.") }
    assert_raises(SpeechNormalizer::Error) { normalize("Концентрация 1 E-3 M.") }
    assert_raises(SpeechNormalizer::Error) { normalize("Концентрация 1e -3 M.") }
    assert_raises(SpeechNormalizer::Error) { normalize("Концентрация 1 E − 3 M.") }
    assert_equal "пять тысяч миллиграммов", normalize("5'000 мг").text
  end

  def test_fractional_leading_zeroes_are_not_spoken_as_extra_digits
    assert_equal "ноль целых пять сотых миллиграмма", normalize("0,05 мг").text
    assert_equal "ноль целых пять тысячных миллиграмма", normalize("0,005 мг").text
  end

  def test_omega_chain_is_not_misread_as_a_negative_range
    assert_equal "омега три, шесть и девять", normalize("омега-3-6-9").text
    assert_equal "Омега три", normalize("Omega-3").text
    assert_equal "омега три", normalize("ω-3").text
  end

  def test_medical_caps_coenzyme_and_international_units
    result = normalize("ACHILLEA MILLEFOLIUM, CoQ10, Q10, 1000 IU, 500 IE и 200 МЕ.")
    assert_equal "Ахиллеа Миллефолиум, коэнзим ку десять, ку десять, " \
                 "одна тысяча международных единиц, пятьсот международных единиц и " \
                 "двести международных единиц.", result.text
    assert_equal "Коэнзим ку десять.", normalize("Коэнзим CoQ10.").text
    assert_equal "коэнзим ку десять и Коэнзим ку десять.", normalize("CoQ-10 и Коэнзим CoQ-10.").text
    assert_equal "пятьсот международных единиц и двести международных единиц.",
                 normalize("500 I.E. и 200 I. E.").text
  end

  def test_dosage_ratios_are_pronounced_instead_of_rejected_late
    assert_equal "пять миллиграммов на килограмм и сто миллиграммов на пять миллилитров.",
                 normalize("5 мг/кг и 100 мг/5 мл.").text
    assert_equal "пять миллиграммов на килограмм и пять миллиграммов на килограмм.",
                 normalize("5 мг кг−1 и 5 мг кг⁻¹.").text
  end

  def test_common_german_and_smart_quotes_are_safe_for_silero
    result = normalize("„Чай “HerbalGem” — O’Connor“")
    assert_equal '"Чай "Хэрбалджем" — О\'Коннор"', result.text
    assert_equal 5, result.audit[:replacements].count { |entry| entry[:kind] == "punctuation" }
  end
end
