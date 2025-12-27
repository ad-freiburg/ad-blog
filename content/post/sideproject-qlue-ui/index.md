---
title: "Qlue-UI, QLever-UI is dead. Long live the QLever-UI."
date: 2025-01-12T12:43:04+02:00
author: "Ioannis Nezis"
authorAvatar: "img/profile.png"
tags: ["editor","SPARQL", "qlever","web-dev"]
categories: []
image: "img/cover.png"
---

After my last project - A fancy new langauge server for SPARQL called **Qlue-ls** -
I planned on plugging this language-server into the QLever-UI.

While technically easy, it felt wrong.  
The code of QLever-UI grew over the years into a real mess.  
I did not want to plug my shiny new engine into a car that feels like
its falling apart. So i did what any reasonable programmer would do 
and started a rewrite.

# Technical overview of QLever-UI

- Django and its limitations
- Codemirronr
- messy js hell

# New Design

- Separate backend and frontend
- monaco + monaco-languageclient
- vite + ts + tailwindcss
- no js-framework

## Details

# Query execution tree

- d3
- layouting a binary tree
- Grandient animations

# Laizy Query execution

# Comparing different engines
