.PHONY: check lint test package-check

check: lint test

lint:
	luacheck .

test:
	busted

# Lists the tracked files CurseForge would package: .pkgmeta's ignore list
# applied to git ls-files, with dotfiles dropped as the packager does.
package-check:
	@git ls-files | grep -v '^\.' | grep -v '/\.' | while read -r f; do \
		sed -n 's/^  - //p' .pkgmeta | grep -qxF "$${f%%/*}" || echo "$$f"; \
	done

