#!/bin/bash
# 全面测试（比 selftest.sh 更彻底，约需几分钟）：
#   1. 转换矩阵：每种可读格式 × 每种可写格式，检查输出合法，并转回文本核对关键文字
#   2. 命令行选项：每个选项都确实改变了输出
#   3. 异常输入：加密、损坏、空文件、扩展名不符、不存在的文件等，都要干净地报错而不是崩溃
#   4. 不覆盖已有文件、文件名含空格和中文、编码识别、界面语言
#   5. 性能：大文档的转换耗时
# 用法：
#   scripts/fulltest.sh                         # 测试 debug 版命令行
#   BIN=dist/DocConverter.app/Contents/MacOS/docconv scripts/fulltest.sh   # 测试打包后的版本
#   PYTHON=/path/to/python scripts/fulltest.sh  # 另外用 python-docx / openpyxl / python-pptx 打开所有 Office 输出
set -uo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
if [ -z "${BIN:-}" ]; then
  swift build --product docconv >/dev/null 2>&1 || { echo "编译失败"; exit 1; }
  BIN="$(swift build --show-bin-path)/docconv"
fi
BIN="$(cd "$(dirname "$BIN")" && pwd)/$(basename "$BIN")"
WORK="$(mktemp -d)"
trap 'chmod -R u+w "$WORK" 2>/dev/null; rm -rf "$WORK"' EXIT
TOOL="$WORK/testtool"
swiftc -O -o "$TOOL" scripts/tools/testtool.swift 2>/dev/null || { echo "测试工具编译失败"; exit 1; }
export LANG=en_US.UTF-8   # 固定界面语言，便于核对提示文字

pass=0; fail=0; FAILS=()
ok()  { pass=$((pass + 1)); }
bad() { fail=$((fail + 1)); FAILS+=("$*"); echo "  ✗ $*"; }
section() { echo; echo "▸ $*"; }

# 运行命令；退出码 ≥ 128 视为崩溃
run() { "$@" >"$WORK/last.log" 2>&1; local c=$?; [ $c -ge 128 ] && bad "崩溃(退出码 $c): $*"; return $c; }

zip_ok() { # 压缩包完整且其中所有 XML 合法
  local f="$1" d="$WORK/_zip"
  rm -rf "$d"; mkdir -p "$d"
  unzip -tq "$f" >/dev/null 2>&1 || return 1
  (cd "$d" && unzip -q "$f") || return 1
  while IFS= read -r p; do xmllint --noout "$p" 2>/dev/null || return 1; done \
    < <(find "$d" -name "*.xml" -o -name "*.rels" -o -name "*.xhtml" -o -name "*.opf" -o -name "*.ncx")
  return 0
}

valid_output() { # 格式 文件
  local t="$1" f="$2"
  [ -s "$f" ] || return 1
  case "$t" in
    docx|pptx|xlsx|epub|odt) zip_ok "$f" ;;
    pdf) local info; info=$("$TOOL" pdfinfo "$f") && [ "${info%% *}" -ge 1 ] ;;
    png|jpg) sips -g pixelWidth "$f" 2>/dev/null | grep -q pixelWidth ;;
    html) xmllint --noout "$f" 2>/dev/null ;;
    json) /usr/bin/python3 -c "import json,sys; json.load(open(sys.argv[1], encoding='utf-8'))" "$f" ;;
    rtf|doc) textutil -convert txt -stdout "$f" >/dev/null 2>&1 ;;
    tex) grep -q '\\documentclass' "$f" ;;
    *) /usr/bin/python3 -c "import sys; open(sys.argv[1], 'rb').read().decode('utf-8')" "$f" 2>/dev/null ;;
  esac
}

# ───────────────────────── 1. 转换矩阵 ─────────────────────────
section "转换矩阵"
IN="$WORK/in"; mkdir -p "$IN"
cp Tests/fixtures/* "$IN/"
# 用内置写出器补齐其余可读格式作为输入
"$BIN" -t rtf -o "$IN" "$IN/sample.md" >/dev/null
"$BIN" -t odt -o "$IN" "$IN/sample.md" >/dev/null
"$BIN" -t doc -o "$IN" "$IN/sample.md" >/dev/null
"$BIN" -t epub -o "$IN" "$IN/sample.md" >/dev/null
"$BIN" -t tsv -o "$IN" "$IN/sample.csv" >/dev/null
"$BIN" -t jpg -o "$IN" "$IN/pic.png" >/dev/null

# 输入文件  通用关键字  表格关键字（导出为表格类格式时核对）
FIXTURES="sample.md 文档转换测试 张三
sample.rtf 文档转换测试 张三
sample.odt 文档转换测试 张三
sample.doc 文档转换测试 张三
sample.epub 文档转换测试 张三
sample.csv 浦东 浦东
sample.tsv 浦东 浦东
report.docx 季度报告 华东
launch.pptx 产品发布会 标准版
data.xlsx 笔记本 笔记本
gb.txt 第二段 第二段
gbk.csv 浦东 浦东
page.html 欢迎 名称
people.json 李四 李四
report.pdf 年度经营报告 张伟
pic.png - -
pic.jpg - -"
OUTS="pdf docx doc pptx xlsx md html txt csv tsv json rtf odt epub tex png jpg"
matrix=0
while read -r file key tkey; do
  base="${file%.*}"; src="${file##*.}"
  for t in $OUTS; do
    [ "$src" = "$t" ] && continue
    o="$WORK/m/${file}_$t"; mkdir -p "$o"
    matrix=$((matrix + 1))
    if ! run "$BIN" -t "$t" -o "$o" "$IN/$file"; then bad "$file → $t: $(tail -1 "$WORK/last.log")"; continue; fi
    outs=$(find "$o" -type f ! -path "*_assets*" | sort)
    [ -n "$outs" ] || { bad "$file → $t: 没有输出文件"; continue; }
    allvalid=1
    while IFS= read -r f; do valid_output "$t" "$f" || { allvalid=0; bad "$file → $t: 输出不合法 $(basename "$f")"; }; done <<<"$outs"
    [ $allvalid -eq 1 ] && ok
    # 转回纯文本核对关键文字
    [ "$key" = "-" ] && continue
    case "$t" in png|jpg|tex) continue ;; esac
    want="$key"; case "$t" in xlsx|csv|tsv) want="$tkey" ;; esac
    text=""
    while IFS= read -r f; do
      b="$WORK/back/$(basename "$o")"; mkdir -p "$b"
      "$BIN" -t txt -o "$b" "$f" >/dev/null 2>&1
      text+=$(cat "$b"/*.txt 2>/dev/null)
    done <<<"$outs"
    grep -q "$want" <<<"$text" && ok || bad "$file → $t → txt: 缺少「${want}」"
  done
done <<<"$FIXTURES"
echo "  共执行 $matrix 次转换"

if [ -n "${PYTHON:-}" ]; then
  section "用第三方库打开 Office 输出（python-docx / openpyxl / python-pptx）"
  res=$("$PYTHON" - "$WORK/m" <<'PY'
import sys, pathlib, docx, openpyxl, pptx
okc = 0; bad = []
for p in sorted(pathlib.Path(sys.argv[1]).rglob("*")):
    if p.suffix not in (".docx", ".xlsx", ".pptx") or "_assets" in str(p): continue
    try:
        if p.suffix == ".docx": docx.Document(str(p))
        elif p.suffix == ".xlsx": openpyxl.load_workbook(str(p))
        else: pptx.Presentation(str(p))
        okc += 1
    except Exception as e:
        bad.append(f"{p.parent.name}/{p.name}: {e}")
print(okc); [print(b) for b in bad]
PY
)
  n=$(head -1 <<<"$res"); errs=$(tail -n +2 <<<"$res")
  [ -z "$errs" ] && { ok; echo "  $n 个文件全部能打开"; } || bad "第三方库无法打开: $errs"
fi

# ───────────────────────── 2. 命令行选项 ─────────────────────────
section "命令行选项"
O="$WORK/opt"; mkdir -p "$O"
for i in 1 2 3 4 5 6; do cat "$IN/sample.md"; echo; done > "$O/long.md"
pdf() { "$TOOL" pdfinfo "$1"; }  # 页数 宽 高 字数

"$BIN" -t pdf -o "$O/a4" "$O/long.md" >/dev/null
read -r p_def w h _ <<<"$(pdf "$O/a4/long.pdf")"
[ "$w" = 595 ] && [ "$h" = 842 ] && ok || bad "默认页面应为 A4，实际 ${w}x${h}"
"$BIN" -t pdf --page letter -o "$O/letter" "$O/long.md" >/dev/null
read -r _ w h _ <<<"$(pdf "$O/letter/long.pdf")"; [ "$w" = 612 ] && [ "$h" = 792 ] && ok || bad "--page letter 实际 ${w}x${h}"
"$BIN" -t pdf --page a3 -o "$O/a3" "$O/long.md" >/dev/null
read -r _ w h _ <<<"$(pdf "$O/a3/long.pdf")"; [ "$w" = 842 ] && [ "$h" = 1191 ] && ok || bad "--page a3 实际 ${w}x${h}"
"$BIN" -t pdf --landscape -o "$O/land" "$O/long.md" >/dev/null
read -r _ w h _ <<<"$(pdf "$O/land/long.pdf")"; [ "$w" -gt "$h" ] && ok || bad "--landscape 实际 ${w}x${h}"
"$BIN" -t pdf --font-size 18 -o "$O/big" "$O/long.md" >/dev/null
read -r p_big _ <<<"$(pdf "$O/big/long.pdf")"; [ "$p_big" -gt "$p_def" ] && ok || bad "--font-size 18 页数应多于默认（$p_big vs ${p_def}）"
"$BIN" -t pdf --margin 20 -o "$O/m20" "$O/long.md" >/dev/null
"$BIN" -t pdf --margin 100 -o "$O/m100" "$O/long.md" >/dev/null
read -r p20 _ <<<"$(pdf "$O/m20/long.pdf")"; read -r p100 _ <<<"$(pdf "$O/m100/long.pdf")"
[ "$p100" -gt "$p20" ] && ok || bad "--margin 100 页数应多于 --margin 20（$p100 vs ${p20}）"
"$BIN" -t docx --page letter --landscape -o "$O/docx" "$IN/sample.md" >/dev/null
(cd "$O/docx" && unzip -p sample.docx word/document.xml | grep -q 'w:orient="landscape"') && ok || bad "Word 输出未设置横向"

# --pdf-mode images：每页一张图，几乎没有文字
"$BIN" -t docx --pdf-mode images -o "$O/img" "$IN/report.pdf" >/dev/null
pages=$(pdf "$IN/report.pdf" | cut -d' ' -f1)
media=$(unzip -l "$O/img/report.docx" | grep -c "word/media/")
[ "$media" = "$pages" ] && ok || bad "--pdf-mode images：图片数 ${media}，应等于页数 $pages"
"$BIN" -t docx -o "$O/txtmode" "$IN/report.pdf" >/dev/null
unzip -p "$O/txtmode/report.docx" word/document.xml | grep -q "年度经营报告" && ok || bad "默认 PDF 读取模式应提取文字"

# 扫描件（只有图片的 PDF）：有无 OCR 都应成功
"$BIN" -t pdf -o "$O/scan" "$IN/pic.png" >/dev/null
run "$BIN" -t md -o "$O/scan_ocr" "$O/scan/pic.pdf" && ok || bad "扫描件 PDF → md 失败"
run "$BIN" -t md --no-ocr -o "$O/scan_noocr" "$O/scan/pic.pdf" && grep -q "!\[" "$O/scan_noocr/pic.md" && ok || bad "--no-ocr 时扫描页应转为图片"

# --split：按一级标题只有 1 节，按二级标题有 3 节
printf '# 总标题\n\n## 第一节\n\n内容一\n\n## 第二节\n\n内容二\n\n## 第三节\n\n内容三\n' > "$O/split.md"
"$BIN" -t pptx --split 1 -o "$O/s1" "$O/split.md" >/dev/null
"$BIN" -t pptx --split 2 -o "$O/s2" "$O/split.md" >/dev/null
n1=$(unzip -l "$O/s1/split.pptx" | grep -cE "ppt/slides/slide[0-9]+\.xml"); n2=$(unzip -l "$O/s2/split.pptx" | grep -cE "ppt/slides/slide[0-9]+\.xml")
[ "$n2" -gt "$n1" ] && ok || bad "--split 2 幻灯片应多于 --split 1（$n2 vs ${n1}）"

# --notes
"$BIN" -t md -o "$O/nonotes" "$IN/launch.pptx" >/dev/null
"$BIN" -t md --notes -o "$O/notes" "$IN/launch.pptx" >/dev/null
grep -q "这里强调续航数据" "$O/notes/launch.md" && ! grep -q "这里强调续航数据" "$O/nonotes/launch.md" && ok || bad "--notes 未生效"

# --embed-images
"$BIN" -t md -o "$O/assets" "$IN/report.docx" >/dev/null
"$BIN" -t md --embed-images -o "$O/embed" "$IN/report.docx" >/dev/null
[ -d "$O/assets/report_assets" ] && grep -q "report_assets/" "$O/assets/report.md" && ok || bad "默认应把图片另存到 _assets"
grep -q "data:image/" "$O/embed/report.md" && [ ! -d "$O/embed/report_assets" ] && ok || bad "--embed-images 未生效"

# --dpi
"$BIN" -t png --dpi 72 -o "$O/d72" "$IN/report.pdf" >/dev/null
"$BIN" -t png --dpi 300 -o "$O/d300" "$IN/report.pdf" >/dev/null
f72=$(find "$O/d72" -name "*.png" | sort | head -1); f300=$(find "$O/d300" -name "*.png" | sort | head -1)
w72=$(sips -g pixelWidth "$f72" | awk '/pixelWidth/{print $2}'); w300=$(sips -g pixelWidth "$f300" | awk '/pixelWidth/{print $2}')
[ "$w300" -gt $((w72 * 3)) ] && ok || bad "--dpi 300 宽度应约为 72 的 4 倍（$w300 vs ${w72}）"

# --libreoffice：未安装时应回退到内置引擎
run "$BIN" -t pdf --libreoffice -o "$O/lo" "$IN/report.docx" && [ -s "$O/lo/report.pdf" ] && ok || bad "--libreoffice 回退失败: $(tail -1 "$WORK/last.log")"

# 其他
"$BIN" --dump "$IN/sample.md" | grep -q "heading" && ok || bad "--dump 未输出中间表示"
[ "$("$BIN" --formats | wc -l | tr -d ' ')" = 17 ] && ok || bad "--formats 应列出 17 种格式"
"$BIN" --help >/dev/null; [ $? = 0 ] && ok || bad "--help 退出码应为 0"
"$BIN" >/dev/null; [ $? = 1 ] && ok || bad "无参数时退出码应为 1"
out=$("$BIN" --bogus "$IN/sample.md"); c=$?; [ $c = 1 ] && grep -q "Unknown option: --bogus" <<<"$out" && ok || bad "未知选项应报错并以 1 退出"
out=$("$BIN" -t nope "$IN/sample.md"); c=$?; [ $c = 1 ] && grep -q "Unknown format: nope" <<<"$out" && ok || bad "未知格式应报错并以 1 退出"
run "$BIN" -t txt -o "$O/new/deep/dir" "$IN/sample.md" && [ -f "$O/new/deep/dir/sample.txt" ] && ok || bad "-o 指向不存在的目录时应自动创建"
for l in zh-Hans zh-Hant en ja ko fr de es; do
  msg=$("$BIN" --lang "$l" -t pdf "$IN/../in/nonexistent.xyz" 2>&1)
  [ -n "$msg" ] && ok || bad "--lang $l 无输出"
done
[ "$("$BIN" --lang zh-Hans -t pdf "$WORK/x.xyz")" != "$("$BIN" --lang de -t pdf "$WORK/x.xyz")" ] && ok || bad "--lang 未改变提示语言"
LANG=ja_JP.UTF-8 "$BIN" --formats | grep -q "^読" && ok || bad "LANG=ja_JP 时应显示日文"
"$BIN" --lang zh-TW --formats | grep -q "^讀" && ok || bad "zh-TW 应匹配繁体中文"

# ───────────────────────── 3. 异常输入 ─────────────────────────
section "异常输入（应报错退出，不能崩溃，不能留下残缺文件）"
E="$WORK/err"; mkdir -p "$E/out"
expect_fail() { # 说明 期望提示片段 命令...
  local what="$1" want="$2"; shift 2
  "$@" >"$WORK/last.log" 2>&1; local c=$?
  if [ $c -ge 128 ]; then bad "${what}：崩溃（退出码 ${c}）"
  elif [ $c -eq 0 ]; then bad "${what}：应失败却成功"
  elif ! grep -q "$want" "$WORK/last.log"; then bad "${what}：提示不符：$(tail -1 "$WORK/last.log")"
  else ok; fi
}
"$TOOL" encrypt "$IN/report.pdf" "$E/locked.pdf"
expect_fail "加密 PDF → docx" "password" "$BIN" -t docx -o "$E/out" "$E/locked.pdf"
expect_fail "加密 PDF → png" "password" "$BIN" -t png -o "$E/out" "$E/locked.pdf"
head -c 4000 /dev/urandom > "$E/broken.docx"; expect_fail "损坏的 docx" "invalid or damaged" "$BIN" -t pdf -o "$E/out" "$E/broken.docx"
head -c 4000 /dev/urandom > "$E/broken.xlsx"; expect_fail "损坏的 xlsx" "invalid or damaged" "$BIN" -t csv -o "$E/out" "$E/broken.xlsx"
head -c 4000 /dev/urandom > "$E/broken.pptx"; expect_fail "损坏的 pptx" "invalid or damaged" "$BIN" -t md -o "$E/out" "$E/broken.pptx"
head -c 4000 /dev/urandom > "$E/broken.pdf";  expect_fail "损坏的 pdf" "invalid or damaged" "$BIN" -t md -o "$E/out" "$E/broken.pdf"
head -c 4000 /dev/urandom > "$E/broken.epub"; expect_fail "损坏的 epub" "invalid or damaged" "$BIN" -t md -o "$E/out" "$E/broken.epub"
head -c 4000 /dev/urandom > "$E/broken.png";  expect_fail "损坏的 png" "invalid or damaged" "$BIN" -t pdf -o "$E/out" "$E/broken.png"
cp "$IN/report.pdf" "$E/fake.docx"; expect_fail "PDF 改名为 .docx" "invalid or damaged" "$BIN" -t md -o "$E/out" "$E/fake.docx"
cp "$IN/data.xlsx" "$E/fake.pptx"; expect_fail "xlsx 改名为 .pptx" "invalid or damaged" "$BIN" -t md -o "$E/out" "$E/fake.pptx"
cp "$IN/data.xlsx" "$E/fake2.docx"; expect_fail "xlsx 改名为 .docx" "invalid or damaged" "$BIN" -t md -o "$E/out" "$E/fake2.docx"
cp "$IN/report.docx" "$E/fake3.xlsx"; expect_fail "docx 改名为 .xlsx" "invalid or damaged" "$BIN" -t csv -o "$E/out" "$E/fake3.xlsx"
cp "$IN/sample.md" "$E/fake4.png"; expect_fail "文本改名为 .png" "invalid or damaged" "$BIN" -t pdf -o "$E/out" "$E/fake4.png"
echo '{"a": [1, 2' > "$E/bad.json"; expect_fail "格式错误的 JSON" "Malformed JSON" "$BIN" -t csv -o "$E/out" "$E/bad.json"
echo "x" > "$E/file.xyz"; expect_fail "不支持的扩展名" "Can’t read this format" "$BIN" -t pdf -o "$E/out" "$E/file.xyz"
echo "x" > "$E/noext"; expect_fail "没有扩展名" "no file extension" "$BIN" -t pdf -o "$E/out" "$E/noext"
expect_fail "不存在的文件" "" "$BIN" -t pdf -o "$E/out" "$E/missing.md"
mkdir -p "$E/folder.md"; expect_fail "目录当作文件" "" "$BIN" -t pdf -o "$E/out" "$E/folder.md"
for ext in md txt csv tsv json html docx xlsx pptx pdf rtf odt epub png jpg doc; do
  : > "$E/empty.$ext"
  "$BIN" -t pdf -o "$E/out_empty" "$E/empty.$ext" >"$WORK/last.log" 2>&1; c=$?
  [ $c -ge 128 ] && bad "空 .$ext 文件：崩溃（退出码 ${c}）" || ok
done
printf '   \n\n  \n' > "$E/blank.md"; expect_fail "只有空白的 md" "no content" "$BIN" -t docx -o "$E/out" "$E/blank.md"
mkdir -p "$E/ro"; chmod 555 "$E/ro"
expect_fail "输出目录只读" "" "$BIN" -t pdf -o "$E/ro" "$IN/sample.md"
chmod 755 "$E/ro"
left=$(find "$E/out" -type f -size 0 | wc -l | tr -d ' ')
[ "$left" = 0 ] && ok || bad "失败的转换留下了 $left 个空文件"

# ───────────────────────── 4. 文件名、覆盖、编码 ─────────────────────────
section "文件名、不覆盖、编码"
N="$WORK/names"; mkdir -p "$N"
cp "$IN/sample.md" "$N/my report 测试 (v2).md"
run "$BIN" -t docx "$N/my report 测试 (v2).md" && [ -f "$N/my report 测试 (v2).docx" ] && ok || bad "含空格和中文的文件名"
"$BIN" -t pdf "$N/my report 测试 (v2).md" >/dev/null; "$BIN" -t pdf "$N/my report 测试 (v2).md" >/dev/null
[ -f "$N/my report 测试 (v2).pdf" ] && [ -f "$N/my report 测试 (v2) (1).pdf" ] && ok || bad "第二次转换应生成 (1) 而不是覆盖"
before=$(md5 -q "$N/my report 测试 (v2).pdf"); "$BIN" -t pdf "$N/my report 测试 (v2).md" >/dev/null
[ "$before" = "$(md5 -q "$N/my report 测试 (v2).pdf")" ] && [ -f "$N/my report 测试 (v2) (2).pdf" ] && ok || bad "已有文件被改动"
"$BIN" -t png -o "$N" "$O/long.md" >/dev/null; "$BIN" -t png -o "$N" "$O/long.md" >/dev/null
[ -d "$N/long" ] && [ -d "$N/long (1)" ] && ok || bad "多页图片输出的文件夹应不覆盖"
"$BIN" -t csv -o "$N/csv" "$IN/data.xlsx" >/dev/null; "$BIN" -t csv -o "$N/csv" "$IN/data.xlsx" >/dev/null
[ "$(ls "$N/csv" | wc -l | tr -d ' ')" -ge 4 ] && ok || bad "多表 CSV 第二次输出应不覆盖"
iconv -f UTF-8 -t UTF-16 "$IN/sample.md" > "$N/utf16.md"
"$BIN" -t txt -o "$N" "$N/utf16.md" >/dev/null && grep -q "文档转换测试" "$N/utf16.txt" && ok || bad "UTF-16 编码识别"
"$BIN" -t md -o "$N" "$IN/gb.txt" >/dev/null && grep -q "第一段文字" "$N/gb.md" && ok || bad "GBK 编码识别"
printf '本季度营收同比增长，其中海外市场表现突出。数据显示用户满意度持续提升。\n' | iconv -f UTF-8 -t GBK > "$N/gbk2.txt"
"$BIN" -t md -o "$N" "$N/gbk2.txt" >/dev/null && grep -q "海外市场" "$N/gbk2.md" && ok || bad "GBK 编码识别（长句）"
printf '繁體中文測試，這是一段臺灣使用的文字。資料處理與轉換\n' | iconv -f UTF-8 -t BIG5 > "$N/big5.txt"
"$BIN" -t md -o "$N" "$N/big5.txt" >/dev/null && grep -q "資料處理與轉換" "$N/big5.md" && ok || bad "Big5 编码识别"
printf '日本語のテキストです。こんにちは世界\n' | iconv -f UTF-8 -t SHIFT_JIS > "$N/sjis.txt"
"$BIN" -t md -o "$N" "$N/sjis.txt" >/dev/null && grep -q "こんにちは世界" "$N/sjis.md" && ok || bad "Shift-JIS 编码识别"
printf '名前,都市\n山田,東京\nさくら,大阪\n' | iconv -f UTF-8 -t SHIFT_JIS > "$N/sjis.csv"
"$BIN" -t json -o "$N" "$N/sjis.csv" >/dev/null && grep -q "さくら" "$N/sjis.json" && ok || bad "Shift-JIS CSV 识别"
printf '氏名,住所\n山田太郎,東京都港区\n鈴木一郎,大阪府北区\n' | iconv -f UTF-8 -t SHIFT_JIS > "$N/kanji.csv"
"$BIN" -t json -o "$N" "$N/kanji.csv" >/dev/null && grep -q "東京都港区" "$N/kanji.json" && ok || bad "只有汉字的 Shift-JIS 识别"
printf 'Größe;Preis\nÜbung für Anfänger;12,50 €\nCafé crème;3,20 €\n' | iconv -f UTF-8 -t CP1252 > "$N/cp1252.csv"
"$BIN" -t json -o "$N" "$N/cp1252.csv" >/dev/null && grep -q "Übung für Anfänger" "$N/cp1252.json" && grep -q "12,50 €" "$N/cp1252.json" && ok || bad "Windows-1252 识别"
printf 'Hello 世界, this is a mostly English line.\n' | iconv -f UTF-8 -t BIG5 > "$N/big5mix.txt"
"$BIN" -t md -o "$N" "$N/big5mix.txt" >/dev/null && grep -q "世界" "$N/big5mix.md" && ok || bad "英文为主的 Big5 文本识别"
printf 'Hello 世界, this is a mostly English line.\n' | iconv -f UTF-8 -t GBK > "$N/gbkmix.txt"
"$BIN" -t md -o "$N" "$N/gbkmix.txt" >/dev/null && grep -q "世界" "$N/gbkmix.md" && ok || bad "英文为主的 GBK 文本识别"
printf '繁體中文測試，這是一段臺灣使用的文字。資料處理與轉換\n' | iconv -f UTF-8 -t GBK > "$N/gbktrad.txt"
"$BIN" -t md -o "$N" "$N/gbktrad.txt" >/dev/null && grep -q "資料處理與轉換" "$N/gbktrad.md" && ok || bad "GBK 编码的繁体中文识别"
printf '\xef\xbb\xbf' > "$N/bom.csv"; cat "$IN/sample.csv" >> "$N/bom.csv"
"$BIN" -t json -o "$N" "$N/bom.csv" >/dev/null && ! grep -q $'\xef\xbb\xbf' "$N/bom.json" && ok || bad "带 BOM 的 CSV：表头不应残留 BOM"
"$BIN" -t csv -o "$N/csvbom" "$IN/sample.csv" >/dev/null
head -c 3 "$N/csvbom/sample.csv" | xxd -p | grep -q efbbbf && ok || bad "CSV 输出应带 BOM（Excel 中文不乱码）"

# 输出中的界面文字随语言变化
"$BIN" --lang zh-Hans -t md --notes -o "$N/zh" "$IN/launch.pptx" >/dev/null
"$BIN" --lang fr -t md --notes -o "$N/fr" "$IN/launch.pptx" >/dev/null
grep -q "演讲者备注" "$N/zh/launch.md" && grep -q "Notes du présentateur" "$N/fr/launch.md" && ok || bad "生成文档中的标签应随语言变化"

# ───────────────────────── 5. 性能 ─────────────────────────
section "性能"
P="$WORK/perf"; mkdir -p "$P"
for i in $(seq 1 40); do cat "$IN/sample.md"; echo; done > "$P/big.md"
{ echo "编号,姓名,城市,金额,日期"; for i in $(seq 1 50000); do echo "$i,用户$i,城市$((i % 300)),$((i * 7 % 10000)).5,2026-01-$((i % 28 + 1))"; done; } > "$P/big.csv"
timed() { local s e; s=$(date +%s); "$@" >/dev/null 2>&1; local c=$?; e=$(date +%s); echo $((e - s)); return $c; }
t1=$(timed "$BIN" -t pdf -o "$P" "$P/big.md"); pages=$(pdf "$P/big.pdf" | cut -d' ' -f1)
echo "  Markdown → PDF（$pages 页）：${t1}s"; [ "$t1" -le 30 ] && ok || bad "大 Markdown → PDF 太慢（${t1}s）"
t2=$(timed "$BIN" -t docx -o "$P" "$P/big.pdf"); echo "  PDF（$pages 页）→ Word：${t2}s"; [ "$t2" -le 30 ] && ok || bad "大 PDF → Word 太慢（${t2}s）"
t3=$(timed "$BIN" -t xlsx -o "$P" "$P/big.csv"); echo "  CSV（5 万行）→ Excel：${t3}s"; [ "$t3" -le 30 ] && ok || bad "大 CSV → Excel 太慢（${t3}s）"
t4=$(timed "$BIN" -t csv -o "$P/back" "$P/big.xlsx"); echo "  Excel（5 万行）→ CSV：${t4}s"
[ "$(wc -l < "$P/back/big.csv" | tr -d ' ')" -ge 50001 ] && ok || bad "5 万行 Excel → CSV 行数不对"

echo
echo "通过 $pass 项，失败 $fail 项"
[ "$fail" -eq 0 ]
