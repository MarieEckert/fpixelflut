.PHONY: all
all: fpf_animated fpf

.PHONY: fpf_animated
fpf_animated:
	fpc fpf_animated.pas -O4

.PHONY: fpf
fpf:
	fpc fpf.pas -O4
