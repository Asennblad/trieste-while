CC=clang++
C_COMPILER=clang
MIN_CMAKE_STANDARD=3.5

RUNS = 50

all: compile

run:
	./build/while build ./examples/$(program).while && cat ./$(program).trieste

# Step 1: configure (cmake)
configure:
	mkdir -p build; cd build; cmake -G Ninja .. \
		-DCMAKE_BUILD_TYPE=Release \
		-DCMAKE_C_COMPILER=$(C_COMPILER) \
		-DCMAKE_CXX_COMPILER=$(CC) \
		-DCMAKE_EXPORT_COMPILE_COMMANDS=1 \
		-DCMAKE_C_FLAGS="-Wno-error" \
		-DCMAKE_CXX_FLAGS="-Wno-error -fno-lto" \
		-DCMAKE_BUILD_WITH_INSTALL_RPATH=ON \
		-DCMAKE_CXX_STANDARD=20

# Step 2: build (ninja)
compile:
	cd build; ninja -j2

fuzz:
	./build/while test -f

clean:
	rm -rf build
	rm -f flamegraph.svg gmon.out out.perf folded.perf perf.data *.trieste

configure-cov:
	mkdir -p build-cov; cd build-cov; cmake -G Ninja .. \
		-DCODE_COVERAGE=ON \
		-DCMAKE_BUILD_TYPE=Debug \
		-DCMAKE_C_COMPILER=$(C_COMPILER) \
		-DCMAKE_CXX_COMPILER=$(CC) \
		-DCMAKE_EXPORT_COMPILE_COMMANDS=1 \
		-DCMAKE_C_FLAGS="-Wno-error" \
		-DCMAKE_CXX_FLAGS="-Wno-error -fno-lto" \
		-DCMAKE_BUILD_WITH_INSTALL_RPATH=ON \
		-DCMAKE_CXX_STANDARD=20

compile-cov:
	cd build-cov; ninja -j2

clean-cov:
	rm -rf build-cov coverage-out

coverage-trieste:
	bash coverage.sh --mode trieste --testcounts $(TESTCOUNTS) --runs $(RUNS) \
		--bin build-cov/while_trieste \
		--src-dir $(shell pwd)/src \
		--exclude "/_deps/" --out-dir coverage-out

coverage-external:
	bash coverage.sh --mode external \
		--external-dir starsmith_tests \
		--bin build-cov/while \
		--src-dir $(shell pwd)/src \
		--exclude "/_deps/" --out-dir coverage-out

clean-coverage:
	rm -rf coverage-out

.PHONY: clean all configure compile run fuzz configure-cov compile-cov clean-cov coverage-trieste coverage-external clean-coverage