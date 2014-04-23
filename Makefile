.PHONY: all clean

all: part1.pdf part1.html part1.epub part2.pdf part2.html part2.epub part3.pdf part3.html part3.epub part4.pdf part4.html part4.epub part4_5.pdf part4_5.html part4_5.epub part5.pdf part5.html part5.epub part6.pdf part6.html part6.epub

clean:
	rm -fv *.aux *.dvi *.log *.pdf *.html *.epub *.out

%.pdf: %.dvi
	dvipdfmx $<

%.dvi: %.tex
	platex $<
	platex $<

%.tex: %.md
	pandoc $< -s -o $@ -V documentclass=jsarticle -V classoption=a4j
	mv $@ $@.tmp
	sed -e s/{article}/{jarticle}/ -e s/\.png/.eps/ $@.tmp > $@
	rm $@.tmp

%.html: %.md
	pandoc $< -s -o $@

%.epub: %.md
	pandoc $< -s -o $@
