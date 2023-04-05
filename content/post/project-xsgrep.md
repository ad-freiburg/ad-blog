---
title: "xs grep: A GNU grep-like executable built with x-search"
date: 2023-04-03T11:09:03+02:00
author: "Leon Freist"
authorAvatar: "img/ada.jpg"
tags: [text search, command line tool, grep]
categories: [project]
image: "img/writing.jpg"
draft: true
---

xs grep is a GNU grep-like executable.
It is built using x-search, a C++ library for fast external string search that was written in the scope of my
bachelor-thesis.
This project aims to introduce xs grep in a more practical way than my thesis did and to provide implementation insights
of xs grep.
Further, reading this post enables you to use x-search's Extended-API within your C++ projects.
The source code of xs grep and x-search is available [here](https://github.com/lfreist/xsgrep).

## Content

1. [Introduction](#introduction)
2. [Using xs grep](#Usage)
3. [Benchmarks](#benchmarks)
4. [Implementation](#implementation)
5. [Conclusion](#conclusion)

## Introduction

Have you ever found yourself struggling with searching a set of large files for a given pattern?
Well, you're not alone.
No matter whether you are a developer or a system administrator.
While developers working in fields such as _bioinformatics_, _natural language processing_ or _information retrieval_
need to search large files for specific patterns within software, system administrators often need to search patterns
within system files such as log-files.

Developers usually need to fall back to their own implementations including reading a file, searching the pattern,
saving the results.
Well, easy...

♫ _Ticking away the moments that make up a dull day,
Fritter and waste the hours in an offhand way_ ♫ (Time, Pink Floyd)

... and... slow?
System administrators are luckier: Most linux distributions come with GNU grep, a command line search tool for searching
patterns within files.
However, what if you could have a GNU grep-like program that is not only faster than GNU grep but also provides a C++
library that can be easily included into your C++ projects, making your custom implementations obsolete and thus, saving
your time?

Well, that's where xs grep comes into play.
Inspired by GNU greps functionality, xs grep takes external searches to the next level:
Performant, customizable, versatile.

Whether you are a developer, a system administrator or just looking for a search tool, xs grep is worth checking out.
In this blog post, we'll take a closer look on xs grep: It's command line tool usage, it's library and how you can
extend and customize it to your specific needs.

## Usage

xs grep provides both, a grep-like executable and a C++ library.
I will first present you its executables usage before guiding you through the process of including the library into your
project.

### The Executable

xs greps executable (`xs`) provides the basic functionalities of GNU grep (well, it's actually me who decided, what's
basic...).

So let's take a look on what's basic for me:

- single file input (no directories)
- single patterns (regex and literal)
  ```
  -F, --fixed-strings   PATTERN is string (not regex)
  -i, --ignore-case     perform case-insensitive search
  ```
- supported output control options:
  ```
  -b, --byte-offset     print the byte offset with output lines
  -n, --line-number     print the line number with output lines
  -o, --only-matching   show only nonempty parts of lines that match
  -c, --count           count the number of matches
  ```

Additionally, xs grep supports some config flags:

```
-m, --metafile    the metafile of a xs grep preprocessed file
-j, --threads     the number of worker threads used for the search
--max-readers     the number of cuncurrently reading threads (default = 1)
--no-mmap         do not use memory mapping
```

#### Examples

| Command                       | Explanation                                                 | Example Output Line                      |
|-------------------------------|-------------------------------------------------------------|------------------------------------------|
| `xs Sherlock sample.txt`      | print all lines within `sample.txt` that contain `Sherlock` | Okay, Sherlock, time for a break, huh?   |
| `xs Sherlock sample.txt -b`   | print the byte offset of the printed line and the line      | 6:Okay, Sherlock, time for a break, huh? |
| `xs Sherlock sample.txt -n`   | print the line number of the printed line and the line      | 2:Okay, Sherlock, time for a break, huh? |
| `xs Sherlock sample.txt -o`   | print the line number of the printed line and the line      | Sherlock                                 |
| `xs Sherlock sample.txt -j 1` | only use a single worker thread                             | Okay, Sherlock, time for a break, huh?   |

So far, so good...
You can see, xs grep can just instantly replace GNU grep for searches on single files.

However, xs grep can do even more!
You may have wondered what the `--metafile` flag is for.
xs greps specific preprocessing includes compression using the LZ4 and ZStandard compression algorithms.
This preprocessing creates a metafile holding some information ion the processed file.
This is a useful feature when you are working on a computer with slow secondary memory such as HDD.
In this case, it can be much faster to read compressed files and then decompress them before searching for the pattern.
Yes, this is only useful, when you are frequently searching files that are relatively static (files that don't change).

> **Example:**
>
> 1. Run the preprocessing: `xspp sample.txt -a zstd -o sample.xszst -m sample.xszst.meta`
> 2. Run the search: `xs Sherlock sample.xszst -m sample.xszst.meta`
>
> The output is equivalent to the output of `xs Sherlock sample.txt`.

The only difference to using xs grep as GNU grep is that you additionally pass the metafile as command line argument
with the `--metafile` (`-m`) flag.

Here is the full information on what options `xspp` supports:

```
Options for xspp:
  -h [ --help ]                    produces this help message.
  --input-file arg                 path to input-file
  -o [ --output-file ] arg         path to output-file (gets overwritten)
  -m [ --meta-file ] arg           path to meta-file (gets overwritten)
  -a [ --compression-alg ] arg     compression alg (zstd, lz4, none (default))
  -l [ --compression-level ] arg   compression level (default: lz4 (only available if used with --hc): 1, zstd: 3)
  --hc                             use high compression algorithm. Only available for lz4.
  -s [ --chunk-size ] arg          number of threads
  -j [ --threads ] arg             size of one chunk that is read
  -d [ --bytes-nl-distance ] arg   number of bytes between new lines that are stored in meta file
```

The `--bytes-nl-distance` flag can be used for saving byte offsets of newline characters.
This is used by xs grep for faster line number searching.

### The library

If you want to integrate the search functionality within your own C++ project, you are at the right place!
The library provided with xs grep can be easily included within your projects.
Since xs grep is built using CMake, I'll show you how to include it into your CMake project:

1. Download xs grep into your projects root directory: `git clone https://github.com/lfreist/xsgrep`
   > If you use git as version control, I recommend including it via git
   modules: `git submodule add https://github.com/lfreist/xsgrep`
2. Copy the following into your projects root `CMakeList.txt`:
   ```cmake
   # CMakeList.txt
   
   # ...
   add_subdirectory(xsgrep)
   include_directories(xsgrep/include)
   # ...
   ```
3. Write your code:
   ```c++
   // main.cpp
   
   #include <xsgrep/grep.h>

   int main() {
       // ...
       Grep grep("Sherlock", "sample.txt");  // search "Sherlock" within "sample.txt"
       auto result = grep.search();
       // ...
   }
   ```
4. Build your project and link xs grep:
   ```cmake
   # CMakeList.txt
   
   # ...
   add_executable(MyProgram main.cpp)
   target_link_libraries(MyProgram PRIVATE libgrep)
   # ...
   ```

#### API

A full API description is available on [GitHub](https://github.com/lfreist/xsgrep/wiki/Library#api) and since API docs
are considered boring, I won't list them here.

## Benchmarks

Within my thesis, I have not only presented comparisons of GNU grep, ripgrep and xs grep, but also discussed the
reasons for the observations with respect to the used search algorithms etc.
If you are interested in such details, I recommend you to check out the *Evaluation* section within my thesis.

### Reading from RAM Cache

Reading data from RAM cache is similar to operating on data that are read into RAM.
A common use case for this is running grep multiple times on the same file (e.g. for searching different patterns).

![cache.png](../../static/img/project-xsgrep/cache.png)

### Reading from HDD

Now let's check out the same benchmarks for reading from HDD...

## Implementation

> **Remark:**
>
> The code snippets I am presenting in this section are simplified and compressed to the basic functionalities.
> The code submitted and available on GitHub is a little more complex and implements tiny features that make it possible
> to use xs grep as C++ library using a simple API.
> I describe the API in the corresponding section [Usage](#Usage).
> Introducing and explaining the full source code is out of the scope of a single blog post.

x-search provides two different kinds of APIs (link):

1. The Single-Call-API that covers the basic searches:
    - searching for matching lines
    - searching for byte offsets
    - searching for line indices
    - counting matching lines or matches
2. The Extended-API that enables developers to extend and optimize components.

Using the Single-Call-API is pretty straight forward and does not require a blog post for introduction.
Therefore, we will use the Extended-API to build a grep-like executable.

### Prerequisites: What Do We Need?

First things first:
The procedure run by x-search is pipeline based.
The wrapper class that executes the pipeline is called `Executor`.
The pipelines tasks must be provided to the `Executor`'s constructor.
The grep-like executable that we are going to implement includes the following tasks:

1. Reading an input file
2. Searching a pattern within the files content
3. Writing the results in the desired format to the console

Concerning the reading task, we make use of one of the predefined task implementations provided within x-search:
The `FileBlockReader`, which reads a file in chunks starting right after and ending with a newline character.
For the searching and printing, we implement a custom searcher and output task respectively.

#### What options do we implement?

We will only implement GNU greps basic options (its actually me who decided, what's basic...):

1. **Search Options**: By default, GNU grep accepts literal or regex patterns.
   However, using the `-F` option, we can force grep to treat regex patterns as literal patterns (e.g. regex specific
   characters are literally searched).
   Further, the `-i` option can be used to perform case-insensitive searches.
2. **Output Control**:
   By default, GNU grep outputs matching lines (lines that contain the given pattern).
   If the `-o` option is set, GNU grep considers actual (substring) matches instead of matching lines.
   For both cases, grep provides the following additional options:
    - Output the corresponding byte offset of a line (or match) (`-b`)
    - Output the corresponding line indices of a line (or match) (`-n`)

Therefore, we implement a searcher, that supports regex and literal searches and provides results that can be formatted
into the output specified by `-o`, `-n` and `-b`.

### Defining a Result Type

We start by defining a result type, representing a single match that all searchers have in common:

```c++
// GrepOutput.h

struct Match {
int64_t byte_offset{
-1
};  // the byte offset of a match or matching line if the -o option is set
int64_t line_number{ -1 };  // the line number if the -n option is set
std::string content;      // the match (if -o option is set) or matching line
};
```

If we have a set of such types in the end, we have everything we need for producing the outputs according to the options
provided.

### Implementing Custom Searchers

Since x-search is pipeline based and the readers used for reading file contents provide chunks of those contents to the
subsequent searchers, the searcher returns a `std::vector<Match>` for every chunk processed.

According to x-search's API reference (todo: link), custom component implementations must inherit the abstract base
class of their intent respectively.
Since a searcher searches for occurrences of a pattern within the provided data and returns the search result, the
searcher is considered a *ReturnProcessor*.
Therefore, our searcher implementation (`GrepSearcher`) must inherit the `xs::task::base::ReturnProcessor<T0, T1>`.
Since we use one of the default readers provided within the x-search library (`FileBlockReader`) which operates on a
string-view-like data structure called `xs::DataChunk`, the searcher operates on objects of the `xs::DataChunk` data
type as well (`T0`).
The second template argument (`T1`) is the result type that `GrepSearcher` produces: `std::vector<Match>`.

The header file for `GrepSearcher` is the following:

```c++
// GrepSearcher.h

#include
<xsearch/xsearch.h>
#include
"./GrepOutput.h"  // for Match

class GrepSearcher :
public xs::task::base::ReturnProcessor<xs::DataChunk, std::vector<Match>> {
public:
// GrepSearcher is initialized with all information needed to create a result that can easily be formatted as intended
// later:
// - pattern:          the pattern that is searched
// - byte_offset  (-b): search byte offsets
// - line_number  (-n): search line numbers
// - match_only   (-o): search matches instead of matching lines
// - fixed_string (-F): search literal pattern
// - ignore_case  (-i): perform case-insensitive searches
GrepSearcher(std::string pattern, bool byte_offset, bool line_number, bool match_only, bool fixed_string, bool ignore_case);

// The process method is abstract within ReturnProcessor. Therefore, we must implement it within this searcher class.
std::vector<Match> process(const xs::DataChunk* data) const override;

private:
std::string _pattern;  // the pattern that is provided
bool _line_number;     // whether to search line numbers or not
bool _byte_offset;     // whether to search byte offsets or not
bool _only_matching;   // whether to search matches or matching lines
bool _regex;           // whether to perform regex search or not
bool _ignore_case;     // whether to perform case-insensitive search or not
std::unique_ptr<re2::RE2> _re_pattern;  // the pattern as regex pattern using RE2
};
```

Since the source code is available, I will not harm you with the implementation of the methods of the `GrepSearcher`.

The important things are:

- `GrepSearcher` inherits `ReturnProcessor<xs::DataChunk, std::vector<Match>>`
- `GrepSearcher` implements `GrepSearcher::process(const xs::DataChunk data)`
- `GrepSearcher::process(data)` is called from the `Executor` and performs the search of `pattern` within `data` while
  considering the options provided.

### Implementing a Custom Result Type

The result type instance (`GrepOutput`) is responsible for collecting the partial results (search results of all
chunks).
The result type is special for implementing a grep-like executable:
Instead of literally collecting results and providing them after the search has completed, `GrepOutput` print all
partial results it receives immediately to the console.

According to x-search's API reference (link), custom result implementations must inherit the abstract base result type
`xs::result::base::Result<T>`.
The template argument (`T`) is our partial result type `std::vector<Match>`.

The header file of `GrepOutput` is the following:

```c++
// GrepOutput.h

class GrepOutput :
public xs::result::base::Result<std::vector<Match>> {
public:
// GrepOutput is initialized with booleans indicating whether byte offset or line number should be printed
GrepOutput(bool byte_offset, bool line_number);

// implementation of the abstract add(T, uint_64_t) method:
// - partial_result is the result of searching a chunk.
// - id is used for printing partial results in their original order. More details are provided below this code
//   fragment.
void add(std::vector<Match> partial_result, uint64_t id) override;

size_t size() const override;

private:
// implementation of the abstract add(T) method:
// This method is called from add(T, uint64_t) and outputs the partial result according to the options (byte_offset,
// line_number)
void add(std::vector<Match> partial_result) override;

bool byte_offsets{ false };  // whether to print byte offsets or not
bool line_numbers{ false };  // whether to print line numbers or not
std::unordered_map<uint64_t, std::vector<Match>> _buffer{};  // A buffer for partial results that must not yet be
// printed. More details below.
uint64_t _current_index{ 0 };  // the index of the next chunks results
};
```

Once again, the implementations of the methods are available on GitHub and I will just state the most important things
here:

- `Executor` passes the partial results to `GrepOutput` by calling `GrepOutput::add(partial_result, id)`
- `GrepOutput::add(partial_result, id)` evaluates `id == _current_index`:
    - If `id == _current_index` evaluates to false, `partial_result` is stored within `_buffer` for later usage
    - If they match, the `partial_result` is passed to `GrepOutput::add(partial_results)` which prints them.
      Further, `_current_index` is increased and if the increased `_current_index` can be found within `_buffer`, the
      corresponding partial result is passed to `GrepOutput::add(partial_results)` as well.
      This repeats until `_current_index` cannot be found within `_buffer`.

You may have noticed the `_buffer` and `_current_index` members of `GrepOutput`.
They are used to output the partial results in the order they occur within the file that was searched.
Since `Executor` (which will run the components later) utilizes multiple threads to concurrently search read chunks, it
may be that the order in which partial results are passed to `GrepOutput` is not the original one.
In this case, the partial results are stored in `_buffer` for later usage as described above.

### Sticking the Peaces Together

Last, we need to stick everything together to build a grep-like command line tool.

```c++
#include "./GrepOutput.h"
#include "./GrepSearcher.h"

int main(int argc, char** argv) {
    // everything we need for searching and outputting:
    struct Options {
        bool line_number = false;
        bool byte_offset = false;
        bool ignore_case = false;
        bool fixed_string = false;
        bool match_only = false;
        std::string pattern;
        std::string file_path;
    } options;
    
    int num_worker_threads = 4;
    
    // We now need to parse argv and map the provided command line arguments to the corresponding member of options.
    // I used boost_program_options for parsing but this requires some lines that I would like to spare you - Its pretty
    // self explanatory and you can find the full source on Github anyways, so I focus on the interesting part here.
    
    // Construct reader, searcher and result:
    auto reader = std::make_unique<xs::task::reader::FileBlockReader>(options.file_path);
    auto searcher = std::make_unique<GrepSearcher>(options.pattern, options.byte_offset, options.line_number,
                                                   options.match_only, options.fixed_string, options.ignore_case);
    auto initial_result = std::make_unique<GrepOutput>(options.byte_offset, options.line_number);
    
    // Construct the Executor:
    auto executor = xs::Executor<
            xs::DataChunk,              // the type of the data that are read and searched
            GrepOutput,                 // the "result" type
            std::vector<Grep::Match>>(  // the partial result type
        num_worker_threads, std::move(reader), {}, std::move(searcher), std::move(initial_result)
    );
    
    // wait for the search to finish
    executor.join();
    return 0;
}
```

As you can see, once the custom tasks are implemented, it's fairly easy to wrap them into the `Executor`.

## Conclusion