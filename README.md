AD Blog
=======
This is the source repository of the [AD
Blog](https://ad-blog.informatik.uni-freiburg.de) which stores all content
including posts and static files such as images. Therefore all posts to the
blog should be added to this repository.

The blog uses the [hugo](https://gohugo.io) site generator and our [custom
theme](https://github.com/ad-freiburg/ad-blog-theme).

## Getting Started
Clone the repository. **Note** that this project uses *git submodule*s and thus
needs to be cloned with

    git clone --recursive https://github.com/ad-freiburg/ad-blog
    cd ad-blog

### Getting hugo
To preview and/or update and post to the blog you currently need **version 0.83.1** (or above)
of the `hugo` static site generator.

If you have `sudo` access on the system and your package manager provides the version mentioned above (or a more recent version), we
recommend installing it with for example

    sudo apt install hugo

Otherwise you can download
a [binary](https://github.com/gohugoio/hugo/releases) for your system and use
it locally or add it to your `$PATH`.

To download just the `hugo` binary on an Intel/AMD Linux system you can use the
following commands. To use the downloaded binary you **must** use `./hugo`
instead of `hugo` in all later commands or make it available on your `$PATH`.

    wget -O - 'https://github.com/gohugoio/hugo/releases/download/v0.83.1/hugo_0.83.1_Linux-64bit.tar.gz' | tar -xvz hugo
    # Test the binary with the version command. Remember you must prepend "./"
    ./hugo version

## Creating a Post

To create a new post first run the following `hugo` command that creates
a skeleton post to be edited with your favorite text editor. Contrary to what
the command suggests the post is created at `content/post/my-awesome-title.md`
which is because **everything that is considered content lives under
`content/`**.

    hugo new post/my-awesome-title.md

It then tells you which file it created. This file can now be filled with all
your awesome content ✍️

The skeleton contains YAML formatted metadata with the following fields. Below
that you will add Markdown formatted content (the Post).

    ---
    title: "My Awesome Title"
    date: 2018-04-12T12:43:04+02:00
    author: "Ada Lovelace"
    authorAvatar: "img/ada.jpg"
    tags: []
    categories: []
    image: "img/writing.jpg"
    draft: true
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

    hugo serve -D --bind "::" --baseURL $(hostname -f)

Here `-D` enables showing of `draft: true` posts and the `--bind` and
`--baseURL` parts ensure that the server is accessible from other systems.
These can be left away when viewing on the same computer.

The above preview only generates the site in-memory, to generate the static
HTML run the following command

    hugo -D

Again, adding `-D` also generates draft posts. The HTML pages for the site are
stored in the `./public` folder. If you're happy with your post you should
change the `draft` metadata to false.

Finally, (if you have the necessary permissions) you can deploy the new version
of the blog with

    ./deploy.sh

This is just an easier way of executing the following commands (where `chmod`
ensures other users in the correct group will be able to apply further
updates).

    hugo
    chmod -R ug+rwX public/
    rsync -avuz public/ ad-blog.informatik.uni-freiburg.de:/var/www/ad-blog/

### Adding Mathematical Formulæ
For adding math [MathJAX](https://www.mathjax.org) has been added and
preconfigured for the use with LaTeX. To render a formular simply add it inline
in a post using double `&` for example `$$x_{1,2} = \frac{-b \pm \sqrt{b^s
-4ac}}{2a}$$`.

### Adding Static Content
Static content can be added to the `static/` folder. It is automatically synced
to the correct destination on building.

## Changing the Title, Description and Menu
These can be changed in the `config.[toml|yaml]` file. However, in the future
the syntax (TOML) may change to match the post metadata (YAML).

## Changing the About Page
The about page is editable through the `content/about.md` file.
