#!/bin/bash
# Build and serve the edit-prediction role (local-edit, ADR 0033). Laptop
# primary: host oMLX does not load this role. Writes only under
# ~/.hearth/models and, for `laptop-up`, the laptop's own oMLX. Never
# touches the host's oMLX, launchd, keys or authorized_keys.
#
#   client/edit-model.sh convert <gguf-repo> <gguf-rev> <gguf-file> <tok-repo> <tok-rev>
#       Download a Qwen2-architecture GGUF at a pinned revision, check its
#       sha256 against the Hub, convert it to MLX 8-bit, and write it to the
#       local-edit `weights` path in config/roles.tsv. The tokenizer is
#       rebuilt from the GGUF's own vocabulary and merges, with
#       <tok-repo>@<tok-rev> as the template for pre-tokenizer and decoder;
#       it must round-trip a code sample. The exact arguments are in docs/MODELS.md
#       (rule 1: no model names here).
#   client/edit-model.sh laptop-up
#       Laptop only: link the weights into this machine's own oMLX
#       (~/.omlx/models/local-edit), pin and load it.
#   client/edit-model.sh bench [--duration S]
#       Gate for laptop local-edit: bench/edit_bench.py against this
#       machine's own oMLX, results under bench/results/<stamp>-edit-laptop.
#   client/edit-model.sh check
#       One timed completion in the edit format against this machine's own
#       oMLX (URL and key from ~/.omlx/settings.json).
#
# Exit 0 ok, 1 failed, 2 could not run.

set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "${ROOT}/scripts/lib.sh"

CMD="${1:-}"; [ $# -gt 0 ] && shift
MODELS="$HOME/.hearth/models"
OMLX_HOME="${OMLX_HOME:-$HOME/.omlx}"

usage() { sed -n '2,27p' "$0"; exit 2; }

# The Python that has mlx and mlx_lm: oMLX's own (from its launcher's
# shebang), or HEARTH_MLX_PY.
mlx_py() {
  local c line
  if [ -n "${HEARTH_MLX_PY:-}" ]; then printf '%s' "$HEARTH_MLX_PY"; return 0; fi
  for c in /opt/homebrew/bin/omlx "$HOME/.omlx/bin/omlx" "$HOME/.omlx/venv/bin/omlx" "$(command -v omlx 2>/dev/null || true)"; do
    [ -n "$c" ] && [ -x "$c" ] || continue
    line=$(head -1 "$c" 2>/dev/null)
    case "$line" in
      '#!'*python*) line="${line#\#!}"; line="${line%% *}"; [ -x "$line" ] && { printf '%s' "$line"; return 0; } ;;
    esac
    [ -x "$(dirname "$c")/python" ] && { printf '%s' "$(dirname "$c")/python"; return 0; }
  done
  return 1
}

edit_row() {
  hearth_edit_roles | awk -F'\t' '$1 == "local-edit" {print; exit}'
}

case "$CMD" in
  convert)
    [ $# -eq 5 ] || usage
    row="$(edit_row)"
    [ -n "$row" ] || { echo "could not run: no local-edit row resolves for this machine's RAM tier (config/roles.tsv)" >&2; exit 2; }
    weights="$(printf '%s' "$row" | cut -f6)"
    out="${MODELS}/${weights}"
    [ -e "$out" ] && { echo "refused: ${out} exists. Move it aside to rebuild." >&2; exit 1; }
    py="$(mlx_py)" || { echo "could not run: no Python with mlx found (set HEARTH_MLX_PY)" >&2; exit 2; }
    "$py" -c 'import mlx.core, mlx_lm, transformers' 2>/dev/null || { echo "could not run: ${py} lacks mlx, mlx_lm or transformers" >&2; exit 2; }
    mkdir -p "$(dirname "$out")"
    "$py" -I - "$1" "$2" "$3" "$4" "$5" "$out" "${MODELS}/.src" <<'PY'
import hashlib, json, os, re, shutil, subprocess, sys, tempfile, urllib.request
import mlx.core as mx

repo, rev, fname, tok_repo, tok_rev, out, src_root = sys.argv[1:]
HEX = re.compile(r"^[0-9a-f]{40}$")
for r in (rev, tok_rev):
    if not HEX.match(r):
        raise SystemExit("refused: revision %r is not a 40-character commit sha" % r)

def get(url, timeout=60):
    req = urllib.request.Request(url, headers={"User-Agent": "hearth-edit-model"})
    return urllib.request.urlopen(req, timeout=timeout)

def fetch(url, dest, want_sha=None):
    if os.path.isfile(dest) and want_sha and sha256(dest) == want_sha:
        print("cached  %s" % os.path.basename(dest)); return
    tmp = dest + ".part"
    h = hashlib.sha256()
    with get(url, 600) as r, open(tmp, "wb") as f:
        while True:
            b = r.read(1 << 20)
            if not b:
                break
            f.write(b); h.update(b)
    if want_sha and h.hexdigest() != want_sha:
        os.remove(tmp)
        raise SystemExit("refused: sha256 of %s is %s, the Hub says %s" % (url, h.hexdigest(), want_sha))
    os.replace(tmp, dest)
    print("fetched %s" % os.path.basename(dest))

def sha256(p):
    h = hashlib.sha256()
    with open(p, "rb") as f:
        for b in iter(lambda: f.read(1 << 20), b""):
            h.update(b)
    return h.hexdigest()

# 1. GGUF at the pinned revision, sha256 from the Hub's LFS record.
src = os.path.join(src_root, repo, rev)
os.makedirs(src, exist_ok=True)
tree = json.load(get("https://huggingface.co/api/models/%s/tree/%s" % (repo, rev)))
entry = next((e for e in tree if e.get("path") == fname), None)
if not entry or not (entry.get("lfs") or {}).get("oid"):
    raise SystemExit("refused: %s not found as an LFS file in %s@%s" % (fname, repo, rev))
gguf = os.path.join(src, fname)
fetch("https://huggingface.co/%s/resolve/%s/%s" % (repo, rev, fname), gguf, entry["lfs"]["oid"])

# 2. Tokenizer files at their pinned revision.
tsrc = os.path.join(src_root, tok_repo, tok_rev)
os.makedirs(tsrc, exist_ok=True)
tok_files = ["tokenizer.json", "tokenizer_config.json", "vocab.json", "merges.txt"]
for t in tok_files:
    fetch("https://huggingface.co/%s/resolve/%s/%s" % (tok_repo, tok_rev, t), os.path.join(tsrc, t))

# 3. Read the GGUF.
w, meta = mx.load(gguf, return_metadata=True)
def m(key, default=None):
    v = meta.get(key, default)
    if isinstance(v, mx.array):
        v = v.item() if v.size == 1 else v.tolist()
    return v
arch = m("general.architecture")
if arch != "qwen2":
    raise SystemExit("refused: GGUF architecture %r; this converter handles qwen2 only" % arch)

# 4. Tokenizer from the GGUF's own vocabulary and merges (a fine-tune may
# prune the vocabulary). The base tokenizer is only the template for the
# pre-tokenizer, decoder and settings.
gtok = m("tokenizer.ggml.tokens") or []
gmerges = m("tokenizer.ggml.merges") or []
gtypes = m("tokenizer.ggml.token_type") or []
if m("tokenizer.ggml.model") != "gpt2" or not gtok or len(gtypes) != len(gtok):
    raise SystemExit("refused: GGUF tokenizer is not a complete gpt2 BPE vocabulary")
vocab = {t: i for i, t in enumerate(gtok)}
if len(vocab) != len(gtok):
    raise SystemExit("refused: GGUF vocabulary has duplicate tokens")
for mg in gmerges:
    parts = mg.split(" ")
    if len(parts) != 2 or parts[0] not in vocab or parts[1] not in vocab or parts[0] + parts[1] not in vocab:
        raise SystemExit("refused: GGUF merge %r does not resolve in its vocabulary" % mg)
tj = json.load(open(os.path.join(tsrc, "tokenizer.json")))
tc = json.load(open(os.path.join(tsrc, "tokenizer_config.json")))
added, decoder = [], {}
for i, (t, ty) in enumerate(zip(gtok, gtypes)):
    if ty in (3, 4):  # control / user-defined
        e = {"id": i, "content": t, "single_word": False, "lstrip": False, "rstrip": False,
             "normalized": False, "special": ty == 3}
        added.append(e)
        decoder[str(i)] = {k: v for k, v in e.items() if k != "id"}
tj["model"]["vocab"] = vocab
tj["model"]["merges"] = list(gmerges)
tj["added_tokens"] = added
eos = gtok[int(m("tokenizer.ggml.eos_token_id"))]
pad_id = m("tokenizer.ggml.padding_token_id")
tc["added_tokens_decoder"] = decoder
tc["additional_special_tokens"] = [e["content"] for e in added if e["special"] and e["content"] not in (eos,)]
tc["eos_token"] = eos
tc["pad_token"] = gtok[int(pad_id)] if pad_id is not None else None
tc["bos_token"] = None
tc.pop("chat_template", None)
tok_stage = tempfile.mkdtemp(prefix="hearth-tok-")
json.dump(tj, open(os.path.join(tok_stage, "tokenizer.json"), "w"), ensure_ascii=False)
json.dump(tc, open(os.path.join(tok_stage, "tokenizer_config.json"), "w"), ensure_ascii=False, indent=2)
json.dump(vocab, open(os.path.join(tok_stage, "vocab.json"), "w"), ensure_ascii=False)
open(os.path.join(tok_stage, "merges.txt"), "w").write("#version: 0.2\n" + "\n".join(gmerges) + "\n")
from transformers import PreTrainedTokenizerFast
ft = PreTrainedTokenizerFast(tokenizer_file=os.path.join(tok_stage, "tokenizer.json"))
sample = 'def greet(name):\n    print(f"Hello, {name}!")  # ünïcode\n<|file_sep|>current/a.py\n'
ids = ft.encode(sample, add_special_tokens=False)
if ft.decode(ids) != sample or vocab["<|file_sep|>"] not in ids:
    raise SystemExit("refused: rebuilt tokenizer does not round-trip a code sample")
print("tokenizer rebuilt from the GGUF: %d tokens, %d merges, %d special; round-trip ok" % (len(gtok), len(gmerges), len(added)))

# 5. Dequantize and rename to Hugging Face Qwen2 names.
def dense(name):
    base = name[: -len(".weight")] if name.endswith(".weight") else name
    q, s, b = w.get(base + ".weight"), w.get(base + ".scales"), w.get(base + ".biases")
    if s is None:
        return w[name]
    in_features = s.shape[-1] * 32
    bits = q.shape[-1] * 32 // in_features
    return mx.dequantize(q, s, b, group_size=32, bits=bits)

per_layer = {
    "attn_norm.weight": "input_layernorm.weight",
    "ffn_norm.weight": "post_attention_layernorm.weight",
    "attn_q.weight": "self_attn.q_proj.weight", "attn_q.bias": "self_attn.q_proj.bias",
    "attn_k.weight": "self_attn.k_proj.weight", "attn_k.bias": "self_attn.k_proj.bias",
    "attn_v.weight": "self_attn.v_proj.weight", "attn_v.bias": "self_attn.v_proj.bias",
    "attn_output.weight": "self_attn.o_proj.weight",
    "ffn_gate.weight": "mlp.gate_proj.weight",
    "ffn_up.weight": "mlp.up_proj.weight",
    "ffn_down.weight": "mlp.down_proj.weight",
}
hf = {}
names = sorted(n for n in w if not n.endswith((".scales", ".biases")))
for n in names:
    if n == "token_embd.weight":
        hf["model.embed_tokens.weight"] = dense(n)
    elif n == "output_norm.weight":
        hf["model.norm.weight"] = dense(n)
    elif n == "output.weight":
        hf["lm_head.weight"] = dense(n)
    elif n.startswith("blk."):
        _, i, rest = n.split(".", 2)
        if rest not in per_layer:
            raise SystemExit("refused: unknown tensor %s" % n)
        hf["model.layers.%s.%s" % (i, per_layer[rest])] = dense(n)
    else:
        raise SystemExit("refused: unknown tensor %s" % n)
hf = {k: v.astype(mx.bfloat16) for k, v in hf.items()}

layers = int(m("qwen2.block_count"))
hidden = int(m("qwen2.embedding_length"))
emb = hf["model.embed_tokens.weight"]
if tuple(emb.shape)[1] != hidden:
    raise SystemExit("refused: embedding shape %s does not match hidden size %d" % (emb.shape, hidden))
config = {
    "architectures": ["Qwen2ForCausalLM"],
    "model_type": "qwen2",
    "hidden_size": hidden,
    "intermediate_size": int(m("qwen2.feed_forward_length")),
    "num_hidden_layers": layers,
    "num_attention_heads": int(m("qwen2.attention.head_count")),
    "num_key_value_heads": int(m("qwen2.attention.head_count_kv")),
    "rms_norm_eps": float(m("qwen2.attention.layer_norm_rms_epsilon")),
    "rope_theta": float(m("qwen2.rope.freq_base", 1000000.0)),
    "max_position_embeddings": int(m("qwen2.context_length")),
    "vocab_size": int(emb.shape[0]),
    "tie_word_embeddings": "lm_head.weight" not in hf,
    "bos_token_id": m("tokenizer.ggml.bos_token_id"),
    "eos_token_id": m("tokenizer.ggml.eos_token_id"),
    "torch_dtype": "bfloat16",
}
print("config: %d layers, hidden %d, vocab %d, tied %s" % (layers, hidden, config["vocab_size"], config["tie_word_embeddings"]))

# 6. Write an HF-shaped folder, then let mlx_lm quantize it to 8-bit.
work = tempfile.mkdtemp(prefix="hearth-edit-")
try:
    stage = os.path.join(work, "hf")
    os.makedirs(stage)
    mx.save_safetensors(os.path.join(stage, "model.safetensors"), hf, metadata={"format": "mlx"})
    json.dump(config, open(os.path.join(stage, "config.json"), "w"), indent=2)
    for t in tok_files:
        shutil.copy2(os.path.join(tok_stage, t), stage)
    tmp_out = out + ".part"
    shutil.rmtree(tmp_out, ignore_errors=True)
    subprocess.run([sys.executable, "-m", "mlx_lm", "convert", "--hf-path", stage,
                    "--mlx-path", tmp_out, "-q", "--q-bits", "8", "--q-group-size", "64"], check=True)
    json.dump({"gguf_repo": repo, "gguf_rev": rev, "gguf_file": fname, "gguf_sha256": entry["lfs"]["oid"],
               "tokenizer_repo": tok_repo, "tokenizer_rev": tok_rev, "quant": "mlx 8-bit, group 64"},
              open(os.path.join(tmp_out, "HEARTH-SOURCE.json"), "w"), indent=2)
finally:
    shutil.rmtree(work, ignore_errors=True)
    shutil.rmtree(tok_stage, ignore_errors=True)

# 7. Sanity: the edit-format example must come back as a plausible edit.
from mlx_lm import load, generate
model, tok = load(tmp_out)
prompt = "\n".join([
    "<|file_sep|>utils.py",
    "def get_time_of_day():\n    from datetime import datetime\n    hour = datetime.now().hour\n    if hour < 12:\n        return \"morning\"\n    elif hour < 18:\n        return \"afternoon\"\n    else:\n        return \"evening\"\n",
    "<|file_sep|>greet.py.diff", "original:", "def greet():\n    print(\"Hello!\")",
    "updated:", "def greet(name):\n    print(f\"Hello, {name}!\")",
    "<|file_sep|>original/greet.py", "def greet(name):\n    print(f\"Hello, {name}!\")\n\ngreet(\"Alice\")",
    "<|file_sep|>current/greet.py", "from utils import get_time_of_day\n\ndef greet(name):\n    print(f\"Hello, {name}!\")\n\ngreet(\"Alice\")",
    "<|file_sep|>updated/greet.py",
])
text = generate(model, tok, prompt=prompt, max_tokens=160, verbose=False)
text = text.split("<|file_sep|>")[0]
print("---- sample prediction ----\n%s\n---------------------------" % text.strip())
if "def greet" not in text:
    shutil.rmtree(tmp_out, ignore_errors=True)
    raise SystemExit("refused: the converted model did not reproduce the file; conversion is wrong")
if "get_time_of_day()" not in text:
    print("WARN: prediction does not use get_time_of_day(); read the sample before trusting it")
os.replace(tmp_out, out)
print("wrote %s" % out)
PY
    rc=$?
    [ "$rc" -eq 0 ] && echo "Next: record the digest (scripts/pin-digests.sh on the host) and bench (scripts/edit-bench.sh)."
    exit "$rc" ;;

  laptop-up)
    [ -d "$HOME/.hearth/models" ] && [ -f "$OMLX_HOME/settings.json" ] || { echo "could not run: needs ~/.hearth/models and ${OMLX_HOME}/settings.json" >&2; exit 2; }
    row="$(edit_row)"; [ -n "$row" ] || { echo "could not run: no local-edit row for this RAM tier" >&2; exit 2; }
    weights="$(printf '%s' "$row" | cut -f6)"; ctx="$(printf '%s' "$row" | cut -f4)"
    src="${MODELS}/${weights}"
    [ -d "$src" ] || { echo "could not run: ${src} missing — run convert first" >&2; exit 2; }
    dest="${OMLX_HOME}/models/local-edit"
    if [ -e "$dest" ] && [ ! -L "$dest" ]; then echo "refused: ${dest} exists and is not a symlink" >&2; exit 1; fi
    ln -sfn "$src" "$dest"
    # Settings, key and port come from the laptop oMLX's own settings file;
    # the key is used in-process and never printed.
    /usr/bin/python3 -I - "$OMLX_HOME/settings.json" "$ctx" <<'PY'
import http.cookiejar, json, sys, time, urllib.error, urllib.request
s = json.load(open(sys.argv[1])); ctx = int(sys.argv[2])
port = (s.get("server") or {}).get("port") or 8000
key = (s.get("auth") or {}).get("api_key") or ""
base = "http://127.0.0.1:%s" % port
jar = http.cookiejar.CookieJar()
op = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(jar))
def call(method, path, body=None, timeout=60):
    req = urllib.request.Request(base + path, method=method,
        data=None if body is None else json.dumps(body).encode())
    req.add_header("Content-Type", "application/json")
    if key: req.add_header("Authorization", "Bearer " + key)
    try:
        with op.open(req, timeout=timeout) as r:
            raw = r.read().decode(); return r.status, (json.loads(raw) if raw else {})
    except urllib.error.HTTPError as e:
        return e.code, {"detail": e.read().decode(errors="replace")[:300]}
    except urllib.error.URLError as e:
        raise SystemExit("could not run: laptop oMLX not answering on %s (%s)" % (base, e.reason))
if key:
    c, _ = call("POST", "/admin/api/login", {"api_key": key})
    if c != 200: raise SystemExit("admin login failed (%s)" % c)
# oMLX discovers new model folders at start; a running server may need a restart.
c, lst = call("GET", "/admin/api/models")
ids = [x.get("id") for x in (lst.get("models") or [])]
if "local-edit" not in ids:
    raise SystemExit("local-edit linked but not discovered: restart the laptop oMLX (brew services restart omlx), then re-run")
c, b = call("PUT", "/admin/api/models/local-edit/settings", {
    "enable_thinking": False, "temperature": 0.0, "max_context_window": ctx,
    "max_tokens": 512, "is_pinned": True, "is_default": False})
if c != 200: raise SystemExit("settings failed (%s): %s" % (c, b))
c, b = call("POST", "/admin/api/models/local-edit/load", None, 300)
if c not in (200, 409): raise SystemExit("load failed (%s): %s" % (c, b))
print("local-edit pinned and loaded on %s" % base)
PY
    exit $? ;;

  bench)
    [ -f "$OMLX_HOME/settings.json" ] || { echo "could not run: ${OMLX_HOME}/settings.json missing" >&2; exit 2; }
    port=$(/usr/bin/python3 -I -c 'import json,sys; print((json.load(open(sys.argv[1])).get("server") or {}).get("port") or 8000)' "$OMLX_HOME/settings.json")
    # The key is read into the environment of the bench process only.
    HEARTH_EDIT_KEY=$(/usr/bin/python3 -I -c 'import json,sys; print((json.load(open(sys.argv[1])).get("auth") or {}).get("api_key") or "")' "$OMLX_HOME/settings.json") \
      /usr/bin/python3 -I "${ROOT}/bench/edit_bench.py" --base-url "http://127.0.0.1:${port}/v1" \
      --key-env HEARTH_EDIT_KEY --out "${ROOT}/bench/results/$(date +%Y-%m-%d-%H%M)-edit-laptop" \
      --label "laptop $(hearth_ram_gb || echo ?) GB, own oMLX" "$@"
    exit $? ;;

  check)
    [ -f "$OMLX_HOME/settings.json" ] || { echo "could not run: ${OMLX_HOME}/settings.json missing" >&2; exit 2; }
    /usr/bin/python3 -I - "$OMLX_HOME/settings.json" <<'PY'
import json, sys, time, urllib.request
s = json.load(open(sys.argv[1]))
url = "http://127.0.0.1:%s/v1" % ((s.get("server") or {}).get("port") or 8000)
key = (s.get("auth") or {}).get("api_key") or ""
prompt = "<|file_sep|>original/a.py\ndef add(a, b):\n    return a + b\n<|file_sep|>current/a.py\ndef add(a, b):\n    return a + b\n\ndef sub(a, b):\n<|file_sep|>updated/a.py\n"
body = {"model": "local-edit", "prompt": prompt, "max_tokens": 64, "temperature": 0, "stop": ["<|file_sep|>"]}
req = urllib.request.Request(url.rstrip("/") + "/completions", data=json.dumps(body).encode())
req.add_header("Content-Type", "application/json")
if key: req.add_header("Authorization", "Bearer " + key)
t = time.time()
d = json.load(urllib.request.urlopen(req, timeout=60))
ms = (time.time() - t) * 1000
text = d["choices"][0].get("text", "")
print("%.0f ms  %r" % (ms, text[:120]))
if "def sub" not in text: raise SystemExit("unexpected prediction")
PY
    exit $? ;;

  *) usage ;;
esac
