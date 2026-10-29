#!/usr/bin/env bash
# Usage: ./build.sh [check|test|examples|run <example>|bench|all]   (default: all)
# Examples build with -debug -o:speed: debug info and bounds checks, release speed.
set -euo pipefail
cd "$(dirname "$0")"

ODIN=${ODIN:-odin}
FLAGS=(-vet -strict-style -warnings-as-errors)
PACKAGES=(. backend input buffer style layout text widgets)

check() {
	for p in "${PACKAGES[@]}"; do
		echo "check $p"
		"$ODIN" check "$p" -no-entry-point "${FLAGS[@]}"
	done
}

test_() {
	echo "test tests"
	"$ODIN" test tests "${FLAGS[@]}" -out:bin/tests
}

examples() {
	mkdir -p bin
	for d in examples/*/; do
		name=$(basename "$d")
		echo "build $name"
		"$ODIN" build "$d" "${FLAGS[@]}" -debug -o:speed -out:"bin/$name"
	done
}

mkdir -p bin
case "${1:-all}" in
	check)    check ;;
	test)     test_ ;;
	examples) examples ;;
	run)      "$ODIN" run "examples/${2:?example name}" "${FLAGS[@]}" -debug -o:speed -out:"bin/$2" ;;
	bench)    "$ODIN" run bench/render "${FLAGS[@]}" -o:speed -out:bin/bench_render ;;
	all)      check; test_; examples ;;
	*)        echo "unknown command: $1" >&2; exit 1 ;;
esac
