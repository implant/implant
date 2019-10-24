.PHONY: build
build:
	docker build -t bakerba/implant .

lint:
	grep -rIl '^#![[:blank:]]*/bin/\(bash\|sh\|zsh\)' \
	--exclude-dir=.git --exclude=*.sw? --exclude=shunit2 \
	. | xargs shellcheck -x
	# List files which name starts with 'Dockerfile'
	# eg. Dockerfile, Dockerfile.build, etc.
	git ls-files --exclude='Dockerfile*' --ignored | xargs --max-lines=1 hadolint

format:
	shfmt -f . | grep -v shunit2 | xargs shfmt -i 2 -ci -w

test:
	docker run -t -v $(shell pwd):/root/implant bakerba/implant test
