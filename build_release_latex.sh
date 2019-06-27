rm -rf BookLatex
# inkscape Book/hashtables/images/basic_hashtable.svg -D -A Book/hashtables/images/basic_hashtable.pdf
# inkscape Book/hashtables/images/doubly_linked_hashtable.svg -D -A Book/hashtables/images/doubly_linked_hashtable.pdf
# inkscape Book/hashtables/images/ordered_hashtable.svg -D -A Book/hashtables/images/ordered_hashtable.pdf
sphinx-build -b latex -d doctrees -a Book BookLatex
cd BookLatex
pdflatex PHPInternalsBook.tex
pdflatex PHPInternalsBook.tex
cd ..
