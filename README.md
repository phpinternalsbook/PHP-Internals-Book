PHP-Internals-Book
==================

Document format: RST
--------------------

The book is written using ReStructured Text and generated using Sphinx.

 * RST manual: http://docutils.sourceforge.net/docs/ref/rst/restructuredtext.html
 * RST quickref: http://docutils.sourceforge.net/docs/user/rst/quickref.html
 * Sphinx manual: http://sphinx.pocoo.org/markup/index.html

Coding style
------------

The following "coding style" applies to the written text, not to the included code.

 * The maximum line-width for text is 120 characters.
 * The maximum line-width for code is 98 characters. Including the four space indentation this would be a limit of 102 characters.
 * Indentation uses four spaces.
 * Lines should not have trailing whitespace.
 * Punctuation like `?`, `!` or `:` should directly follow after the word (e.g. `foo:` rather than `foo :`).

Domains
-------

These domains have been bought by Anthony to publish info about the book:

 * phpinternalsbook.com
 * phpcorebook.com
 * insidephpbook.com

The idea is to publish the TOC and some preview chapters publicly through those
domains, that way people can follow the progress and stay interested in the
project.

Target Audience
---------------

 * C Developers - The primary target audience so that new developers can contribute and extend PHP core
 * Non-C Developers - The secondary target audience so that people who don’t know C can still understand what’s going on and why things are implemented how they are
 * PHP users - Sure, this book may have some interest for everydays PHP developers that may be curious about how their common language work. Knowing the internals makes developers better.

Remember that C Developers don’t really need a book to understand what’s going on in PHP’s heart as the source code is publicly available and not *that* hard to understand for a good-knowledge C developer.

We may then focus for people that have little knowledge about system programming under Unix
 * I don’t think this is true. Even if you know C very well you will have a hard time figuring out how stuff works in PHP. It’s very sparsely commented and the concepts are not usually documented. - nikic
 * I agree, but from my experience, all I’ve learnt is nearly by only reading source code ;) - Julien
 * Yes, same for me too. And I didn’t like that :P Would have preferred reading it ^^
   * +1 !

Goals, Why
----------

 * The main goal is to show how PHP works from inside, and how to extend it through extensions and/or source patching.
 * This also includes how to build PHP, and we should cover at least Linux and Windows, for Windows we’ll get helped by Pierre
 * Also, we would dedicate this book to PHP contributors and show all the work that’s been done and that most PHP users simply ignore.
 * Finally we should find some way to justify some choices and design implementations inside PHP

Authors
-------

* Julien Pauli: jpauli@php.net
* Nikita Popov: nikic@php.net
* Anthony Ferrara: ircmaxell@php.net
