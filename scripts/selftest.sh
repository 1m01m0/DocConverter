#!/bin/bash
# 自测：把 Tests/fixtures 中的样例转换成所有输出格式，再转回 Markdown，检查：
#   1) 每一步都成功；2) Office/EPUB 输出的 ZIP 与 XML 完整合法；3) 关键文字在往返后仍在。
set -uo pipefail
cd "$(dirname "$0")/.."
swift build --product docconv >/dev/null 2>&1 || { echo "编译失败"; exit 1; }
BIN="$(swift build --show-bin-path)/docconv"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
cp Tests/fixtures/* "$WORK/"
cd "$WORK"

pass=0; fail=0
ok()   { pass=$((pass + 1)); }
bad()  { fail=$((fail + 1)); echo "  ✗ $*"; }

check_zip() { # 文件的绝对路径
  local f="$1" d="$WORK/_x"
  rm -rf "$d"; mkdir -p "$d"
  unzip -tq "$f" >/dev/null 2>&1 || { bad "ZIP 损坏: $f"; return; }
  (cd "$d" && unzip -q "$f") || { bad "无法解压: $f"; return; }
  [ -n "$(ls -A "$d")" ] || { bad "压缩包为空: $f"; return; }
  while IFS= read -r p; do
    xmllint --noout "$p" 2>/dev/null || { bad "XML 不合法: $(basename "$f") → ${p#$d/}"; return; }
  done < <(find "$d" -name "*.xml" -o -name "*.rels" -o -name "*.xhtml" -o -name "*.opf" -o -name "*.ncx")
  ok
}

echo "▸ sample.md → 所有格式 → Markdown"
for t in pdf docx doc pptx xlsx html txt csv tsv json rtf odt epub tex png jpg; do
  mkdir -p "o_$t"
  if "$BIN" -t "$t" -o "o_$t" sample.md >/dev/null; then ok; else bad "md → $t"; continue; fi
  case "$t" in docx|pptx|xlsx|epub|odt) check_zip "$WORK/o_$t/sample.$t" ;; esac
  case "$t" in tex|png|jpg) continue ;; esac
  out=$(ls "o_$t" | grep -v _assets | head -1)
  mkdir -p "b_$t"
  if "$BIN" -t md -o "b_$t" "o_$t/$out" >/dev/null; then ok; else bad "$t → md"; continue; fi
  md=$(cat "b_$t"/*.md)
  # 表格类格式只保留表格；其余格式应保留标题
  case "$t" in
    xlsx|csv|tsv) grep -q "张三" <<<"$md" && ok || bad "$t 往返后缺少表格内容" ;;
    *) grep -q "文档转换测试" <<<"$md" && grep -q "张三" <<<"$md" && ok || bad "$t 往返后缺少关键文字" ;;
  esac
done

echo "▸ sample.csv → xlsx / json / docx"
for t in xlsx json docx; do
  "$BIN" -t "$t" sample.csv >/dev/null && ok || bad "csv → $t"
done
"$BIN" -t md -o csvback sample.xlsx >/dev/null && grep -q "上海, 浦东" csvback/sample.md && ok || bad "csv → xlsx → md 内容不一致"

echo "▸ 图片 → PDF → PNG"
"$BIN" -t pdf pic.png >/dev/null && "$BIN" -t png -o picback pic.pdf >/dev/null && [ -f picback/pic.png ] && ok || bad "图片往返"

echo
echo "通过 $pass 项，失败 $fail 项"
[ "$fail" -eq 0 ]
