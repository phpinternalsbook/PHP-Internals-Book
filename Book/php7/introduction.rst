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

PHP 8 and the 8.x series
-------------------------

.. versionadded:: PHP 8.0

This section of the book also covers PHP 8 and the subsequent 8.x releases. PHP 8 is built
directly on the PHP 7 foundation. The core data structures -- zvals, hashtables, ``zend_string``,
and the Zend memory manager -- are unchanged. Most chapters apply equally to both versions.

Where behaviour or APIs changed in PHP 8, the differences are explicitly noted inline with a
coloured callout box stating the PHP version in which the change was introduced. Sections that
cover concepts that exist only in PHP 8 (fibers, enums, the JIT compiler, attributes, the
observer API) carry such a notice at the very top of the section.

The PHP 8.x release timeline:

* **PHP 8.0** (November 2020) -- JIT compiler, union types, named arguments, attributes,
  match expressions, constructor property promotion. Object handlers API cleaned up (now
  accept ``zend_object*`` instead of ``zval*``). TSRM compatibility macros removed. All
  internal functions now required to declare arginfo.
* **PHP 8.1** (November 2021) -- Fibers (coroutines), enums, readonly properties,
  intersection types, first-class callable syntax, ``never`` return type.
* **PHP 8.2** (December 2022) -- Readonly classes, disjunctive normal form (DNF) types,
  standalone ``null``/``true``/``false`` types.
* **PHP 8.3** (November 2023) -- Typed class constants, ``#[\Override]`` attribute. C99
  compiler formalised as a hard requirement.
* **PHP 8.4** (November 2024) -- Property hooks, asymmetric visibility,
  ``#[\Deprecated]`` attribute, frameless function calls for faster internal dispatch.
