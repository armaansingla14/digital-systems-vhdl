# Requires ghdl and python3 on PATH. On a machine without them, use
# scripts/docker_run.sh, which runs these targets inside a container
# (e.g. `scripts/docker_run.sh make test`).

.PHONY: test waves pytest asm clean

test:            ## analyse, elaborate and run every testbench + ISS cross-check
	python3 scripts/run_tests.py

waves:           ## same, but also dump GHW waveforms into build/
	python3 scripts/run_tests.py --waves

pytest:          ## unit tests for the assembler and ISS (needs pytest)
	python3 -m pytest -q tests

asm:             ## assemble all programs into build/
	mkdir -p build
	for f in programs/*.asm; do python3 tools/asm.py $$f -o build/$$(basename $$f .asm).hex -l build/$$(basename $$f .asm).lst; done

clean:
	rm -rf build
