PHP-Internals-Book
==================

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

Schedule
--------

 * Aug 27 - Sept 3 - Add ideas on topics to write about (can be organized or not)
 * Sept 3 - Sept 10 - Organize ideas into rough outline of book. Have an organized TOC
 * Sept mid - Oct mid - Start writing some chapters
 * Oct mid - Nov 1st - Have a lookback and agree finally on the writing styles, the RST format
 * Nov 1st - First public announce of the project. From this point, no way-back possible, ppl will be expcting our work, so we’ll have to finish it ;-)

Todo
----

 * Find a publisher and a licence (free book ? half-free ? Print only (no pdf) ) ?
 * Contact eventual partial contributors that would be needed (Pierre, Ekneuss, Mike, anyone we’ll need eventually)

Misc
----

 * It takes about a year long to write a book, from the beginning idea to the final print book ; though we can finish the work in about 4 months if we really work hard on it daily, that won’t be the case I think ;-)
 * Don’t hesitate to draw pictures. Drawings are much more explanatory than texts and make the global reading feel more comfortable
 * Don’t worry about the total amount of sheets, write what you want, simply think about the global reading and balance
 * Some of us may have difficulties in English writing. When you write a book, at the end of the process stands a big step of reading, spell checking and fixing. It is recommended to read and read again what’s been written all through the project life, and fix words and sentences, living less work for the final step, usually the most boring one.

Writing format
--------------

We agreed on using ReStructured Text (http://docutils.sourceforge.net/rst.html). It is similar to Markdown, but has additional features that are probably important for us:

 * Internal and external references, footnotes, etc
 * Directives: Extensible mechanism to markup stuff. E.g. there could be a directive for the C info bubbles, etc. There is a large number of directives already built in, many of which are also relevant for us: http://docutils.sourceforge.net/docs/ref/rst/directives.html
 * Also has support for TOCs and stuff (again, via directives)
 * Here is the QuickRef: http://docutils.sourceforge.net/docs/user/rst/quickref.html
 * Generally a quite powerful language, but still having simple enough syntax, so we don’t have to deal with something like DocBook

Storing sources
---------------

We agreed to share our sources privately using the private GitHub repo from ircmaxell
So we use git together with a github remote.
Remember that sources must include drawings and all form of binary data we may provide

https://github.com/ircmaxell/PHP-Internals-Book
