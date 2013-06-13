Packages versus sources
=======================

This short chapter is aimed for remembering you about a crucial thing : PHP as we describe during this whole book, is what you grab from http://www.php.net.
We guess you should be used to your OS, Unix based we hope. So you may know about your package distribution system.
For example, on Debian based OSes, the *apt* tool is used to grab packages from package repositories. You then could use such a command to easilly install PHP on your system :

.. code-block:: none

    #> apt-get install php
    
Then what your system will do is grab some PHP binaries from the repository you setup for the *apt* tool, and install it in a default tree, such as */usr/bin*, */etc*, */usr/lib*,  etc...

What we would like to advise you here, is that what is installed using this method *may not be* the same product as what could come from http://www.php.net. What comes from a package repository is a product that your package repository manager did put in, not what the crew from php.net provided.
In most time, you'll end up with the exact same product, and the PHP crew works together with some people responsible of packaging PHP for some OSes, Fedora is a good example of that. But be warned if you use a repository to get PHP installed on your system.

For example, in Debian back from the 6.0 version and earlier, what was stored in the default apt repository coming with this system was not the exact same PHP, compared to what you can grab from http://www.php.net.
In fact, the guys who turned PHP from sources to packages, *patched the version*, adding some stuff such as "suhosin", which is a known patch providing more security to the PHP default source (from what suhosin author says). But it is known and it's been proven with time that this patch also introduces some slow down in PHP engine and in its memory manager, as well as some code that happened to be incompatible with some extensions, in some cases, such as OPCode cache extensions.

And this becomes even more complex if you run a company supported OS, such as Red Hat for example. In this case, what you grab from the package manager is also not the same product as comes from http://www.php.net. Red Hat company could have pacthed PHP, in their manner, so that they better master what they distribute and can provide some support to their customers related to the software they host in their package repo.

In any way, the PHP team does not support such software from distributions. The only version of PHP that the PHP crew supports is the one coming from http://www.php.net.
We sometimes get asked about "PHP from Debian", or "PHP from Suse", or "PHP from whatever you want". We don't master what the guys behind those versions do to the real sources we provide from http://www.php.net.

This chapter was short, but now you know what we talk about in this book, and what the PHP team supports : the "PHP" software, coming from any mirror behind php.net domain.
