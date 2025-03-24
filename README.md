AD Blog
=======

This is the source repository of the [AD Blog](https://ad-blog.informatik.uni-freiburg.de).

The blog uses the [hugo](https://gohugo.io) site generator.

## Getting Started

Clone the repository.

    git clone --recursive https://github.com/ad-freiburg/ad-blog
    cd ad-blog

### Getting hugo

To preview and/or update and post to the blog you currently need
**version 0.145.0** (or above) of the `hugo` static site generator.

> [!WARNING]
> Depending on your Linux, the `hugo` version in your packet-manager
> repositoty may be to old.
> In this case install `hugo` the [binary-asset provided on github](https://github.com/gohugoio/hugo/releases/tag/v0.145.0)

For more information go to the [hugo website](https://gohugo.io/installation/)

## Creating a Post

To create a new post first run the following `hugo` command that creates
a skeleton post to be edited with your favorite text editor.

    hugo new post/<your-title>/index.md

It then tells you which file it created. This file can now be filled with all
your awesome content ✍️

The skeleton contains YAML formatted metadata with the following fields. Below
that you will add Markdown formatted content (the Post).

    ---
    title: "My Title"
    date: 2018-04-12T12:43:04+02:00
    author: "Ada Lovelace"
    authorAvatar: "img/ada.jpg"
    tags: []
    categories: []
    image: "img/writing.jpg"
    ---

This should be customized to the post and author.

After this (in the same file) you can now append your summary and content using
Markdown format.

    Summary goes here

    <!--more-->

    Content goes here. This uses Markdown in the
    [Blackfriday](https://github.com/russross/blackfriday) variant

You can then preview your new post using the web server built into `hugo` with
the following command

    hugo serve

If `hugo` runs on a different machine than the browser you want to use, run:

    hugo serve --bind "::" --baseURL <hostname>

Where `<hostname>` is the hostname of the machine where `hugo` is running.

The above preview only generates the site in-memory, to generate the static
HTML run the following command

    hugo

The HTML pages for the site are stored in the `./public` folder.

### Adding Mathematical Formulæ

For adding math [MathJAX](https://www.mathjax.org) has been added and
preconfigured for the use with LaTeX. To render a formular simply add it inline
in a post using double `$` for example `$$x_{1,2} = \frac{-b \pm \sqrt{b^s
-4ac}}{2a}$$`.

### Adding Static Content

Static content, like images, can be added to the `content/<your-title>/img/` folder.
