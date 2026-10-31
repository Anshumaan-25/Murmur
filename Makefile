.PHONY: test app run check demo bench
check:
	python3 scripts/cleanroom_check.py
test:
	swift run murmur-tests
app:
	bash scripts/build_app.sh
run: app
	open .build/Murmur.app
demo:
	bash scripts/demo.sh
bench:
	swift run -c release murmur-bench
