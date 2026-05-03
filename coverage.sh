set -euo pipefail

MODE="trieste"          # trieste | external | both
FUZZ_MODE="f"           # f (./while test -f)  or  c (./while test -c <number>)
RUNS=1                  # number of runs (per testcount if fuzz-mode=c, otherwise in total)
TESTCOUNTS=(100)        # only used if FUZZ_MODE=c
BIN=""                  # path to the binary to analyze, e.g. build/while
SRC_DIR=""              # path to sorce files to analyze
EXCLUDE="/_deps/"       # regex for files to be excluded from coverage report
OUT_DIR="coverage-out"  # output directory for coverage reports
EXTERNAL_DIR=""         # directory conatining external .while test files (if mode=external or both)
 
# path to LLMV tools
LLVM_COV="${LLVM_COV:-llvm-cov-18}"
LLVM_PROF="${LLVM_PROF:-llvm-profdata-18}"
 
# parse command line arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --mode)         MODE="$2";         shift 2 ;;
        --fuzz-mode)    FUZZ_MODE="$2";    shift 2 ;;
        --runs)         RUNS="$2";         shift 2 ;;
        --bin)          BIN="$2";          shift 2 ;;
        --src-dir)      SRC_DIR="$2";      shift 2 ;;
        --exclude)      EXCLUDE="$2";      shift 2 ;;
        --out-dir)      OUT_DIR="$2";      shift 2 ;;
        --external-dir) EXTERNAL_DIR="$2"; shift 2 ;;
        --testcounts)
            TESTCOUNTS=()
            shift
            while [[ $# -gt 0 && "$1" != --* ]]; do
                TESTCOUNTS+=("$1")
                shift
            done
            ;;
        *) echo "Unknown argument: $1"; exit 1 ;;
    esac
done
 
# validation
if [[ -z "$BIN" || -z "$SRC_DIR" ]]; then
    echo "Fel: --bin och --src-dir krävs."
    exit 1
fi
if [[ ! -f "$BIN" ]]; then
    echo "Fel: binären '$BIN' finns inte."
    echo "Bygg med: cmake -DCODE_COVERAGE=ON -DCMAKE_CXX_COMPILER=clang++ .."
    exit 1
fi
if [[ "$MODE" == "external" || "$MODE" == "both" ]] && [[ -z "$EXTERNAL_DIR" ]]; then
    echo "Fel: --external-dir krävs när --mode är 'external' eller 'both'."
    exit 1
fi
if [[ "$FUZZ_MODE" != "f" && "$FUZZ_MODE" != "c" ]]; then
    echo "Fel: --fuzz-mode måste vara 'f' eller 'c'."
    exit 1
fi
 
OUT_DIR="${OUT_DIR%/}"
mkdir -p "$OUT_DIR"
 

# functions
generate_profdata() {
    local output="$1"; shift
    echo "    Mergar → $(basename "$output")"
    "$LLVM_PROF" merge -sparse "$@" -o "$output"
}
 
generate_coverage_json() {
    local profdata="$1"
    local out_json="$2"
    echo "    JSON   → $out_json"
    "$LLVM_COV" export "$BIN" \
        -instr-profile="$profdata" \
        -format=text \
        -ignore-filename-regex="$EXCLUDE" \
        "$SRC_DIR" > "$out_json"
}
 
generate_coverage_html() {
    local profdata="$1"
    local out_dir="$2"
    echo "    HTML   → $out_dir/index.html"
    "$LLVM_COV" show "$BIN" \
        -instr-profile="$profdata" \
        -format=html \
        -ignore-filename-regex="$EXCLUDE" \
        -output-dir="$out_dir" \
        "$SRC_DIR"
}
 
print_summary() {
    local profdata="$1"
    echo ""
    "$LLVM_COV" report "$BIN" \
        -instr-profile="$profdata" \
        -ignore-filename-regex="$EXCLUDE" \
        "$SRC_DIR"
}
 
# run binary once and save profile in specified .profraw file.
run_once() {
    local profraw="$1"
    local tc="${2:-100}"
    LLVM_PROFILE_FILE="$profraw" "$BIN" test -c "$tc" 2>/dev/null || true
}
 
# merge all .profraw files
_aggregate_and_report() {
    local dir="$1"; shift
    local profraw_files=("$@")
 
    local agg_dir="$dir/aggregated"
    mkdir -p "$agg_dir"
    local profdata="$agg_dir/aggregated.profdata"
 
    generate_profdata "$profdata" "${profraw_files[@]}"
    generate_coverage_json "$profdata" "$agg_dir/aggregated.json"
    generate_coverage_html "$profdata" "$agg_dir/coverage-html"
    print_summary "$profdata"
}
 
# trieste fuzzer
run_trieste_coverage() {
    echo ""
    echo "=== Trieste fuzzer (--fuzz-mode $FUZZ_MODE) ==="
    local trieste_out="$OUT_DIR/trieste"
    mkdir -p "$trieste_out"
 
    if [[ "$FUZZ_MODE" == "f" ]]; then
        local group_dir="$trieste_out/fuzz_f"
        mkdir -p "$group_dir"
        echo "  Runs $RUNS times with -f..."
 
        local profraw_files=()
        for ((run=1; run<=RUNS; run++)); do
            echo "  Run $run/$RUNS"
            local profraw="$group_dir/run_${run}.profraw"
            run_once "$profraw"
            [[ -f "$profraw" ]] && profraw_files+=("$profraw")
        done
 
        _aggregate_and_report "$group_dir" "${profraw_files[@]}"
 
    else
        for tc in "${TESTCOUNTS[@]}"; do
            echo ""
            echo "  Testcount: $tc ($RUNS runs)"
            local tc_dir="$trieste_out/$tc"
            mkdir -p "$tc_dir"
 
            local profraw_files=()
            for ((run=1; run<=RUNS; run++)); do
                echo "    Run $run/$RUNS"
                local profraw="$tc_dir/run_${run}.profraw"
                run_once "$profraw" "$tc"
                [[ -f "$profraw" ]] && profraw_files+=("$profraw")
            done
 
            _aggregate_and_report "$tc_dir" "${profraw_files[@]}"
        done
    fi
}
 
# external test files (from starsmith)
run_external_coverage() {
    echo ""
    echo "=== External test files ($EXTERNAL_DIR) ==="
    local ext_out="$OUT_DIR/external"
    mkdir -p "$ext_out"
 
    shopt -s nullglob
    local files=("$EXTERNAL_DIR"/*.while)
    shopt -u nullglob
 
    if [[ ${#files[@]} -eq 0 ]]; then
        echo "  No .while files found in $EXTERNAL_DIR"
        return 1
    fi
    echo "  Found ${#files[@]} files."
 
    local profraw_files=()
    for f in "${files[@]}"; do
        local base
        base=$(basename "$f" .while)
        local profraw="$ext_out/${base}.profraw"
        echo "  → $base.while"
        LLVM_PROFILE_FILE="$profraw" \
            "$BIN" build "$f" -o /dev/null 2>/dev/null || true
        [[ -f "$profraw" ]] && profraw_files+=("$profraw")
    done
 
    if [[ ${#profraw_files[@]} -eq 0 ]]; then
        echo "  No .profraw files generated."
        return 1
    fi
 
    _aggregate_and_report "$ext_out" "${profraw_files[@]}"
}
 
# combined report for both trieste and external
run_combined_report() {
    echo ""
    echo "=== Combined report (trieste + external) ==="
    local combined_out="$OUT_DIR/combined"
    mkdir -p "$combined_out"
 
    local all_profraw=()
    while IFS= read -r f; do
        all_profraw+=("$f")
    done < <(find "$OUT_DIR/trieste" "$OUT_DIR/external" \
                  -name "*.profraw" 2>/dev/null | sort)
 
    if [[ ${#all_profraw[@]} -eq 0 ]]; then
        echo "  No .profraw files found."
        return 1
    fi
 
    _aggregate_and_report "$combined_out" "${all_profraw[@]}"
    echo ""
    echo "  Combined HTML: $combined_out/aggregated/coverage-html/index.html"
}
 
# main
echo "Coverage-skript starting..."
echo "  Binary:   $BIN"
echo "  Source code: $SRC_DIR"
echo "  Output directory: $OUT_DIR"
echo "  Mode:    $MODE"
[[ "$MODE" != "external" ]] && echo "  Fuzz:    --fuzz-mode $FUZZ_MODE"
 
case "$MODE" in
    trieste)
        run_trieste_coverage
        ;;
    external)
        run_external_coverage
        ;;
    both)
        run_trieste_coverage
        run_external_coverage
        run_combined_report
        ;;
    *)
        echo "Unknown mode: $MODE"
        exit 1
        ;;
esac
 
echo ""
echo "Done! Reports saved in: $OUT_DIR"