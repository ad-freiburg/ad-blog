---
title: "Project Testing Qlever Control With Mocking"
date: 2024-12-22T16:24:05+01:00
author: "Simon Lempp"
tags: ["mocking", "unittests", "testing", "QLever", "qlever-control"]
categories: ["project"]
image: "/img/project-testing-qlever-control-with-mocking/headnote.png"
draft: true
---



## Content

1. [Introduction](#introduction)

2. [Qlever-control script](qlever-control-script)

3. [Goals](#goals)

4. [Mocking](#mocking)

5. [Approach](#approach)

   - [Test example](#test-example)

   - [Code optimisation](#code-optimisation)

6. [Conclusion and future work](#conclusion-and-future-work)


----


## 1. Introduction {#introduction}
The [QLever](https://qlever.cs.uni-freiburg.de/) SPARQL engine was developed at the Chair of Algorithms and Data
Structures at the University of Freiburg. It can efficiently search through terabytes of data with the help of queries and Output information very quickly. QLever can be operated with the help of a "qlever-control" script written in Python. When programming QLever, great importance is attached to efficient, comprehensively tested and well documented code. So far, the qlever-control script has only been tested end-to-end and no unit tests.

## 2. Qlever-control script {#qlever-control-script}
The qlever-control script contains commands written in Python that can be used to operate the SPARQL engine. Some of these commands are described below.

The start and stop commands can be used to stop running QLever server processes and then start the engine on a free port (start.py; stop.py). Running QLever processes can be displayed with the status command (status.py). Logging and debugging during runtime is realised with the help of the logging system (log.py). The index of a given RDF dataset is constructed in index.py. The cache.py file can be used to output statistics and details of the cache memory.

## 3. Goals {#goals}
The aim of this project was to write unit tests for the commands Python files. Due to time constraints, this was limited to the QLever commands start, status, stop, index, cache and log described above. In addition, the readability of the code of the commands Python files was to be improved. Testing was implemented particularly efficiently using the mocking method. This project should help to ensure a high quality of the qlever-control script code. 

## 4. Mocking {#mocking}
In mocking, an object is imitated with the help of a mock object. This is most commonly used in unittesting. Mocking allows functions with complex dependencies to be tested in Isolation by imitating the dependencies in the test using mock objects. For example, if a command line for the index is created and executed in index.py, the execution can be mocked. This allows to check whether the execution command was called with the correct parameters. The start-stop command for the engine can also be checked for correctness without actually starting the server for each test. Error messages can also be intercepted and tested with mocking. 
In the mock object library [unittest.mock](https://docs.python.org/3/library/unittest.mock.html) in Python, the object is first converted into a mock object with "patch". The return value of the mock object can then be set as required using "return_value". Mocking can be particularly helpful when testing functions
that make use of many auxiliary functions.


## 4. Approach {#approach}
Before starting to write tests, I had to familiarise myself with the topic of mocking, the operation of github and the structure of Python files. As the Python programming language was already familiar from my studies, I only needed to learn how to test functions efficiently with the help of mocking. 

The files were analysed, were written for the execute function in a Python commands file of the same name and tests were written for the other functions in a separate Python file. In total over 70 tests were written. Every effort was made to test every line of code (line coverage). If errors occurred in the code, a pull request was made to improve the code. If the code lost readability due to long code blocks, which weren't essential for understanding the function, suggestions for improvement were submitted. This was usually achieved with the help of outsourced functions that shortened the execute function of the command files and were then also tested. 

### Example for testing an execute function using the log.py file {#test-example}
Figure 1: Basic Test for log

```
   @patch('subprocess.run')
   @patch('qlever.commands.log.log')
   # Test execute of index command for basic case with successful execution
   def test_execute_beginning_without_no_follow(self, mock_log, mock_run):
        # Setup args
        args = MagicMock()
        args.name = "TestName"
        args.from_beginning = True
        args.no_follow = False
        args.show = False

        # Instantiate LogCommand and execute the function
        result = LogCommand().execute(args)

        # Assertions
        log_file = f"{args.name}.server-log.txt"
        expected_log_cmd = f"tail -n +1 -f {log_file}"
        expected_log_msg = (f"Follow log file {log_file}, press Ctrl-C "
                            f"to stop following (will not stop the server)")
        # Check that the info log contains the exception message
        mock_log.info.assert_has_calls([call(expected_log_msg), call("")],
                                       any_order=False)

        # Checking if run_command was only called once
        mock_run.assert_called_once_with(expected_log_cmd, shell=True)

        assert result
```
Most of the tests were similar in design and structure. All tests of a file were written in a class Test*Command, where * stood for the file name. A basic test was then written, which simulated the typical sequence of the execute function without special cases and with successful execution (see Figure 1). As each Python file was to be tested separately, the functions were tested in isolation instead of with all sub-functions. For this purpose, the relevant sub-functions were mocked for each test (Figure 1, line 8f.). This offered the advantage that sub-functions that required long execution times, large amounts of data or complicated data formats could be simulated. It was possible to check whether the function was called with the correct parameters in the correct sequence (Figure 1, lines 23-32). It was also checked for the sub-functions whether only the intended calls and no other calls were made. To ensure that the function could be run through without error, the outcome of the auxiliary functions also had to be simulated in some tests. When mocking the auxiliary functions, care was taken to ensure that the data type of the parameters and the outcome was not changed. The execute functions were given an "args" class object as an argument. This was also simulated using the "MagikMock()" mock object (Figure 1, line 13). The individual properties of "args" could then be set in such a way that the desired path was traversed in the execute (Figure 1, lines 12-17). At the end of a test, it was checked whether the mocked functions were called with the correct parameters in the correct order. The return value of the execute function was also checked.

Outside the basic test, tests were carried out for special cases, various branches of the branches and for failed runs. Figure 2 shows a section of such a test. The error message for the failure of a sub-function was intercepted and replaced by another one (Figure 2, lines 102- 105). It was then possible to check whether the modified error message occurred when executing the function with the mocked "args". 

Figure 2: Test for failed attempt when executing the subprocess.run command
```
    @patch('subprocess.run')
    @patch('qlever.commands.log.log')
    # test for failed subprocess.run
    def test_execute_failed_to_run_subprocess(self, mock_log,
                                                      mock_run):
        # Setup args
        args = MagicMock()
        args.name = "TestName"
        args.from_beginning = False
        args.no_follow = True
        args.show = False
        args.tail_num_lines = 50

        # Assertions
        # Simulate a command execution failure
        error_msg = Exception("Failed to run subprocess.run")
        mock_run.side_effect = error_msg

```

When writing the tests, care was taken to observe the required form templates such as line length and blank lines. In addition, each line within the code of the execute function was covered with a test, thus ensuring line coverage. The tests were commented with the required information. This resulted in comprehensible, easy-to-read code. A similar procedure was used for the tests for the auxiliary functions outside the execute function.


### Code optimisation {#code-optimisation}

In some places, suggestions for improving the code were formulated. For example, the execute function of the stop.py file consisted of 58 lines of code in which some processes were executed that were necessary for the preparation of the stop, but did not belong directly to the stop process. By outsourcing code to a stop_process and a stop_container auxiliary function, the execute function could be reduced to 44 lines. This increased the clarity of the execute function. It was also easier to test, as the new auxiliary functions were tested separately and could be mocked within the execute function for testing.
Individual errors in the code were also found and corrected. 


## 5. Conclusion and future work {#conclusion-and-future-work}

In summary, it can be said that the work of the IT project has comprehensively tested and optimised the code of the commands files examined. Attention was paid to welldocumented and clear code. Suggestions for improving existing code were also made and errors in the code were pointed out. This enabled the project's objectives to be met.

The remaining command files still need to be tested in future work. The tests of the commands files can serve as a guide for testing with mocking. This can save a lot of time when writing unit tests.

However, mocking also has the disadvantage that it harbours the risk of only testing the code in isolated code components. Tests should therefore also be written for the interaction of the commands without mocking.






















