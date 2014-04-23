.PHONY: all clean

all: part1.pdf part1.html part2.pdf part2.html part3.pdf part3.html part4.pdf part4.html part4_5.pdf part4_5.html part5.pdf part5.html

clean:
	rm -rf *.aux *.dvi *.log *.pdf *.html

%.pdf: %.dvi
	dvipdfmx $<

%.dvi: %.tex
	platex $<
	platex $<

%.html: %.tex
	latex2html -mkdir -dir $@ $<
