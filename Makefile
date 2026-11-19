.PHONY: check lint test package-check release-notes release

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

# Release steps, as CONTRIBUTING.md#releasing describes. CHANGELOG lets
# release-notes edit another file, such as a scratch copy.
CHANGELOG ?= CHANGELOG.md

release-notes:
	@scripts/release.sh notes "$(VERSION)" "$(CHANGELOG)"

release:
	@scripts/release.sh tag "$(VERSION)"
