Introduction
============

This book is a collaborative effort between several developers of the PHP language to better document and describe how
PHP works internally.

There are three primary goals of this book:

 * Document and describe how PHP internals work.
 * Document and describe how to extend the language with extensions.
 * Document and describe how you can interact with the community to develop PHP itself.

This book is primarily targeted at developers who have experience in the C programming language. However, wherever
possible we will attempt to distill the information and summarize it so that developers who don't know C well, will
still be able to understand the content.

However, let us insist. You won't be able to achieve something productive, stable (crash free under any platform),
performant and useful, if you don't know the C language. Here are some pretty nice online resources about the C
language itself, its ecosystem and build tools, and Operating System APIs:

* http://www.tenouk.com/
* https://en.wikibooks.org/wiki/C_Programming
* http://c-faq.com/
* https://www.gnu.org/software/libc/
* http://www.faqs.org/docs/Linux-HOWTO/Program-Library-HOWTO.html

We also highly recommend you some books. You'll learn with them how to efficiently use the C language, and how to
make it translate to efficient CPU instructions so that you can design strong/fast/reliable and secure programs.

* The C Programming Language (Ritchie & Kernighan)
* Advanced Topics in C Core Concepts in Data Structures
* Learn C the Hard Way
* The Art of Debugging with GDB DDD and Eclipse
* The Linux Programming Interface
* Advanced Linux Programming
* Hackers Delight
* Write Great Code (2 Volumes)

.. note:: This book is Work-In-Progress and some chapters have not been written yet. We don't pay attention to a
          specific order, but add content as we feel.

The repository for this book is available on GitHub_. Please report issues and provide feedback on the `issue tracker`_.

.. _GitHub: https://github.com/phpinternalsbook/PHP-Internals-Book
.. _issue tracker: https://github.com/phpinternalsbook/PHP-Internals-Book/issues
