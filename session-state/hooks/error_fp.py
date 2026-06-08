# error 指纹计数器（PostToolUse / error-loop-guard 增强版）
# 由 error-loop-guard.sh 调用：stdin = 当前 Bash 工具的 RESULT 文本；argv[1] = 本会话 sessions 目录。
# 逻辑：从 RESULT 抽「错误特征行」-> 归一化成指纹 -> 在 per-session 指纹计数文件(error.fps)里 +1
#       -> 输出该指纹累计次数 + 摘要（count<TAB>summary），供 sh 判断是否达阈值。
# 与旧 PreToolUse 回看版的区别：失败数据由 sh 当场从 tool_response 传入，不再回看 jsonl
# （已证实 Bash 失败走 PostToolUse、error-loop-guard 在此触发有效；回看 jsonl 那条路是误判产物）。
import sys, re, os, json

try:
    sys.stdout.reconfigure(encoding='utf-8')
except Exception:
    pass

# 从长输出里挑出「错误特征行」做指纹依据。比 sh 的 gate 正则更全：
# 必须纳入「error CS0116」这类错误码行——它判别性最强，不能只抓到无差别的「Build FAILED」，
# 否则不同编译错（CS0116 vs CS0246）会被误并成同一个指纹。
ERR_LINE = re.compile(
    r'(error\s+[A-Z]{2,6}\d+'        # 编译/构建错误码：error CS0116 / error MSB3021（判别性最强）
    r'|error:|^error'                # error: xxx / 行首 error
    r'|exception|traceback'          # 运行时异常
    r'|^fail|failed|fatal'           # 失败/致命
    r'|exit code [1-9]'              # 非 0 退出码
    r'|cannot access|no such file|command not found|permission denied)',
    re.IGNORECASE)

def normalize(s):
    s = s.replace("<tool_use_error>", "").replace("</tool_use_error>", "")
    s = re.sub(r'[A-Za-z]:\\[^\s"]+', '<PATH>', s)          # Windows 路径
    s = re.sub(r'(?<![\w])(?:/[\w.\-]+){2,}', '<PATH>', s)  # POSIX 路径
    s = re.sub(r'(?<![A-Za-z])\d+', 'N', s)                 # 孤立数字->N（CS0116 等字母后数字保留）
    s = re.sub(r'\s+', ' ', s).strip()
    return s

def fingerprint(result):
    # 优先用命中失败特征的行做指纹；抽不到（理论上 sh 已 gate）则退回尾部 300 字
    lines = [ln.strip() for ln in result.splitlines() if ERR_LINE.search(ln)]
    basis = ' '.join(lines) if lines else result[-300:]
    return normalize(basis)[:200]

def main():
    dirp = sys.argv[1] if len(sys.argv) > 1 else '.'
    result = sys.stdin.read()
    fp = fingerprint(result)
    if len(fp) < 8:   # 指纹太短，信息不足，不计
        return
    store = os.path.join(dirp, 'error.fps')
    data = {}
    if os.path.exists(store):
        try:
            data = json.load(open(store, encoding='utf-8'))
        except Exception:
            data = {}
    cnt = data.get(fp, 0) + 1
    data[fp] = cnt
    try:
        with open(store, 'w', encoding='utf-8') as f:
            json.dump(data, f, ensure_ascii=False)
    except Exception:
        pass
    print("%d\t%s" % (cnt, fp[:120]))   # count <TAB> 摘要，供 sh 解析

if __name__ == '__main__':
    main()
