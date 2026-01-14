pub-get:
	for dir in */ ; do \
		if [ -d "$$dir" ] && [ -f "$$dir/pubspec.yaml" ]; then \
			(cd "$$dir" && flutter pub get); \
		fi \
	done