#!/usr/bin/env bash
# Usage: ./build.sh [check|test|examples|run <example>|all]   (default: all)
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
		"$ODIN" build "$d" "${FLAGS[@]}" -debug -out:"bin/$name"
	done
}

mkdir -p bin
case "${1:-all}" in
	check)    check ;;
	test)     test_ ;;
	examples) examples ;;
	run)      "$ODIN" run "examples/${2:?example name}" "${FLAGS[@]}" -debug -out:"bin/$2" ;;
	all)      check; test_; examples ;;
	*)        echo "unknown command: $1" >&2; exit 1 ;;
esac
