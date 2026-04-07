# Careful about copy/pasting, Makefiles want tabs!
# But you're not copy/pasting, are you?
.PHONY: update
switch:
	nh os switch -H deepthought .

boot:
	nh os boot -H deepthought .

build:
	nh os build -H deepthought .
