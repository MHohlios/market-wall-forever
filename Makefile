.PHONY: check lint test

check: lint test

lint:
	luacheck .

test:
	busted
