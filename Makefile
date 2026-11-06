.PHONY: test app run install check demo bench
check:
	python3 scripts/cleanroom_check.py
test:
	swift run murmur-tests
app:
	bash scripts/build_app.sh
install: app
	bash scripts/install_app.sh
run: app
	open .build/Keydown.app
demo:
	bash scripts/demo.sh
bench:
	python3 scripts/benchmark.py
