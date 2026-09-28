# frozen_string_literal: true

require "securerandom"
require "digest"
require "time"
require "tempfile"

# Reports are private runtime data, not files next to the user's lectures.
class VoiceoverReports
  DEFAULT_DIRECTORY = File.expand_path("~/Library/Logs/SRTtoSound")
  MARKER = "SRTtoSound completed report v1\n"
  NAME = /\Avoiceover-\d{8}T\d{6}Z-[0-9a-f-]{36}\.report\.txt\z/
  MAX_AGE = 3 * 24 * 60 * 60

  def initialize(directory = DEFAULT_DIRECTORY)
    @directory = File.expand_path(directory)
  end

  def prepare
    raise VoiceoverError, "Папка отчётов не должна быть ссылкой: #{@directory}" if File.symlink?(@directory)
    FileUtils.mkdir_p(@directory, mode: 0o700)
    raise VoiceoverError, "Нет доступа к папке отчётов: #{@directory}" unless File.directory?(@directory) && File.writable?(@directory)
  end

  def cleanup(now: Time.now)
    return 0 unless File.exist?(@directory) || File.symlink?(@directory)
    prepare
    removed = 0
    Dir.children(@directory).each do |name|
      next unless name.match?(NAME)
      path = File.join(@directory, name)
      begin
        stat = File.lstat(path)
        next unless stat.file? && stat.uid == Process.uid && stat.mtime < now - MAX_AGE
        # NOFOLLOW also prevents following a link substituted after lstat.
        File.open(path, File::RDONLY | File::NOFOLLOW) do |file|
          next unless file.stat.ino == stat.ino && file.read(MARKER.bytesize) == MARKER
          current = File.lstat(path)
          next unless current.file? && current.ino == stat.ino && current.mtime == stat.mtime
          File.unlink(path)
          removed += 1
        end
      rescue Errno::ENOENT, Errno::ELOOP
        next
      end
    end
    removed
  end

  def publish(source, input:, output:)
    prepare
    name = "voiceover-#{Time.now.utc.strftime('%Y%m%dT%H%M%SZ')}-#{SecureRandom.uuid}.report.txt"
    path = File.join(@directory, name)
    Tempfile.create([".pending-", ".txt"], @directory) do |file|
      file.binmode
      file.write(MARKER)
      file.write("Источник: #{input}\nЗапрошенный путь аудио: #{output}\nСоздан: #{Time.now.iso8601}\n\n")
      File.open(source, "rb") { |report| IO.copy_stream(report, file) }
      file.flush
      file.fsync
      File.link(file.path, path) # No overwrite, even on UUID collision.
    end
    path
  end

  def publish_outcome(input:, output:, status:, detail:)
    prepare
    name = "voiceover-#{Time.now.utc.strftime('%Y%m%dT%H%M%SZ')}-#{SecureRandom.uuid}.report.txt"
    path = File.join(@directory, name)
    Tempfile.create([".pending-", ".txt"], @directory) do |file|
      file.binmode
      file.write(MARKER)
      file.write("Источник: #{input}\nЗапрошенный путь аудио: #{output}\nСоздан: #{Time.now.iso8601}\nСтатус: #{status}\n\n#{detail}\n")
      file.flush
      file.fsync
      File.link(file.path, path)
    end
    path
  end
end

class VoiceoverSkipped < StandardError; end
class VoiceoverCancelled < StandardError; end

# The GUI answers via JSON on stdin. Noninteractive CLI defaults to a copy.
# Explicit replacement is committed only after audio validation. A changed file
# requires a new decision; the user's old answer never authorizes a new target.
class VoiceoverDestination
  attr_reader :path

  def initialize(path, input:, policy: "copy", cancelled:, &ask)
    @base = @path = path
    @input, @policy, @cancelled, @ask = input, policy, cancelled, ask
    @copy = false
    @approved = nil
    raise VoiceoverError, "Неизвестное действие при совпадении имени" unless %w[copy ask skip replace].include?(policy)
  end

  def snapshot
    stat = File.lstat(@path)
    [stat.dev, stat.ino, stat.size, stat.mtime.to_r, stat.ctime.to_r, stat.mode]
  rescue Errno::ENOENT
    nil
  end

  def resolve
    loop do
      raise VoiceoverCancelled if @cancelled.call
      current = snapshot
      return @path unless current
      return @path if @approved == current
      if @approved && @policy != "ask"
        raise VoiceoverError, "Файл изменился после разрешения на замену. Запустите задание снова: #{@path}"
      end
      @approved = nil
      if File.file?(@path) && File.identical?(@path, @input)
        raise VoiceoverError, "Выходной файл совпадает с исходным SRT"
      end
      can_replace = File.lstat(@path).file?
      choice = @copy ? "copy" : @policy
      choice = @ask.call(@path, can_replace) if choice == "ask"
      raise VoiceoverCancelled if @cancelled.call
      case choice
      when "skip" then raise VoiceoverSkipped
      when "replace"
        raise VoiceoverError, "Нельзя заменять папку или символическую ссылку. Сохраните копию." unless can_replace
        # If the file changed while the user was deciding, ask again.
        next unless current == snapshot
        @approved = current
        return @path
      when "copy"
        @copy = true
        extension = File.extname(@base)
        stem = @base.delete_suffix(extension)
        number = 2
        begin
          @path = "#{stem} (#{number})#{extension}"
          number += 1
        end while snapshot
      else
        raise VoiceoverError, "Не получен ответ на вопрос о сохранении файла"
      end
    end
  end

  def publish(audio)
    loop do
      resolve
      raise VoiceoverCancelled if @cancelled.call
      if @approved
        # Same-volume rename is atomic: no partial audio is ever exposed.
        next unless @approved == snapshot
        File.rename(audio, @path)
      else
        begin
          File.link(audio, @path)
        rescue Errno::EEXIST
          next # Another job/file appeared after the preflight.
        end
      end
      return @path
    end
  end
end
