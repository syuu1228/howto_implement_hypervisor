.PHONY: all clean

all: part1.pdf part1.html part1.epub part2.pdf part2.html part2.epub part3.pdf part3.html part3.epub part4.pdf part4.html part4.epub part4_5.pdf part4_5.html part4_5.epub part5.pdf part5.html part5.epub part6.pdf part6.html part6.epub part7.pdf part7.html part7.epub part8.pdf part8.html part8.epub part9.pdf part9.html part9.epub part10.pdf part10.html part10.epub part11.pdf part11.html part11.epub part12.pdf part12.html part12.epub part15.pdf part15.html part15.epub part16.pdf part16.html part16.epub part17.pdf part17.html part17.epub part18.pdf part18.html part18.epub part19.pdf part19.html part19.epub part20.pdf part20.html part20.epub

clean:
	rm -fv *.aux *.dvi *.log *.pdf *.html *.epub *.out

%.pdf: %.dvi
	dvipdfmx $<

%.dvi: %.tex
	platex $<
	platex $<

%.tex: %.md
	pandoc $< -s -o $@ -V documentclass=jsarticle -V classoption=a4j --default-image-extension=.eps

%.html: %.md
	pandoc $< -s -o $@ --default-image-extension=.png

%.epub: %.md
	pandoc $< -s -o $@ --default-image-extension=.png

%.mobi: %.epub
	~/kindlegen/kindlegen $<
