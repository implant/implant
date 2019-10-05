.PHONY: build
build:
	docker build \
	-t bakerba/implant .

lint:
	grep -rIl '^#![[:blank:]]*/bin/\(bash\|sh\|zsh\)' \
	--exclude-dir=.git --exclude=*.sw? \
	| xargs shellcheck -x
	# List files which name starts with 'Dockerfile'
	# eg. Dockerfile, Dockerfile.build, etc.
	git ls-files --exclude='Dockerfile*' --ignored | xargs --max-lines=1 hadolint
