#!/bin/zsh
set -euo pipefail
VOICEOVER_PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd -P)"
cd "$VOICEOVER_PROJECT_DIR"
/usr/bin/ruby tests/test_gui_job.rb
/usr/bin/ruby tests/test_aac_export.rb
/usr/bin/ruby tests/test_release_1_2.rb
/usr/bin/ruby tests/test_release_1_2_1.rb
/usr/bin/ruby tests/test_release_1_2_2.rb
/usr/bin/ruby tests/test_release_1_3.rb
/usr/bin/ruby tests/test_speech_normalizer.rb
/usr/bin/ruby tests/test_public_export.rb
VOICEOVER_TEST_DIR="$(mktemp -d -t srt-queue-tests)"
trap '/bin/rm -f "$VOICEOVER_TEST_DIR/queue-tests"; /bin/rmdir "$VOICEOVER_TEST_DIR"' EXIT
/usr/bin/xcrun swiftc GUI/QueueSupport.swift tests/QueueSupportTests.swift \
  -module-cache-path GUI/build/module-cache -o "$VOICEOVER_TEST_DIR/queue-tests"
"$VOICEOVER_TEST_DIR/queue-tests"
