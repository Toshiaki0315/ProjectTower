#!/bin/bash
# 画面確認用テストを、いくつかに分けて並べて実行する（速く終わらせるため）。
#
#   tools/run_tests.sh [分ける数]   （省略すると3つ）
#
# 各組は別のGodotのウィンドウで動く。結果は最後にまとめて表示する。
set -u
cd "$(dirname "$0")/.."
count=${1:-3}
out=$(mktemp -d)
echo "テストを${count}組に分けて実行します..."
for i in $(seq 1 "$count"); do
  TEST_SHARD="$i/$count" godot --path . -s res://tests/screenshot_test.gd -- "$out/shots_$i" > "$out/log_$i.txt" 2>&1 &
done
wait
ok=$(grep -hcE "^  OK" "$out"/log_*.txt | paste -sd+ - | bc)
ng=$(grep -hcE "^  NG" "$out"/log_*.txt | paste -sd+ - | bc)
echo "OK ${ok}項目 / NG ${ng}項目"
if [ "$ng" -gt 0 ]; then
  grep -hE "^  NG|SCRIPT ERROR" "$out"/log_*.txt
  echo "RESULT: FAILED（ログ: $out）"
  exit 1
fi
echo "RESULT: ALL PASSED（ログ: $out）"
