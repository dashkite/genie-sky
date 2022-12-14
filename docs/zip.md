# Implementation Guide

*Zip Bundling For AWS Lambda*

**Dan Yoder**

A fair amount of effort has gone into the implementation of our zip bundler for AWS Lambdas. This document is intended to help ensure that we don’t replicate any of that effort again later.

## Background

In principle, what we want seems simple: to use sourcemaps when debugging AWS Lambda functions. In practice, this turns out to be difficult, probably because we’re using CoffeeScript and we’re generating sourcemaps when we build. Build tools like Webpack and ESBuild seem to assume that they’re responsible for generating sourcemaps. Some tools offer a variety of configuration options and it’s possible that there’s a way to do handle this scenario. It’s also possible to configure the build process so that it’s handled by the bundler. However, all of these approaches rely on non-standard, idiosyncratic interfaces that require that our modules be configured to suit the bundler. It’s fair to say that we had a second, tacit objective: to rely on simple and standard configurations for our build process.

Even if we try to stick to standards—including de facto standards within the Node ecosystem—keeping it simple remains a challenge. Modules may use a variety of different ways to tell a package manager which files to include in a module, each of which may involve numerous rules. To provide just one example, NPM’s `package.json` has `main`, `modules`, and sometimes `browser` to indicate entry points, the `files` property that provides a Git-ignore style list of files and directories, and an `exports` property to support ESM. A given module may use any or all of these. What’s more, there’s no module—at least that I could find—that encapsulates all this complexity in such a way that you can simply point at a module and say, please give me all the files this module might use. Which is surprising, given the number of bundlers out there—Webpack, Parcel, Rollup, SnowPack, ESBuild, among others—each of which apparently implements this functionality without making it available independent of the bundler itself.

I probably spent the bulk of the time researching ways to configure bundlers to do what we wanted and trying to bootstrap using existing libraries, mostly because it seemed implausible that there wasn’t a straightforward way to do what we wanted. This effort did not yield any useful result. Of course, I probably overlooked something, but the very fact that I wasn’t able to find a solution reasonably quickly is the real problem. Even if we found a winning configuration, it would be brittle and difficult to reason about. And it’s equally difficult to build a solution because, again, the building blocks are coupled to the bundlers and package managers. It shouldn’t be this way, and there’s a whole discussion we could have about how badly this ecosystem is broken, but, for our purposes here, all we need to say is to approach with caution. Hopefully, the approach we’re using will serve us for the foreseeable future.

Another approach I tried and discarded was to use Atlas. This worked but was slow because Atlas is slow. Atlas is slow because it assumes that it needs to load everything from the Web. But it was the right idea: `npm publish` has already done the work of figuring out which files to include, so we can leverage that. See _Implications For Atlas_ below.

### The Breakthrough

The trick to our approach is that, Instead of loading from NPM or (or an NPM-based CDN), we simply use the local filesystem. We assume that you’ve run `npm install` for any local dependencies and, thus, we can use the installed files to figure out which files we need. From there, we place them in a zip file instead of bundling them. This works perfectly well for AWS Lambda. In fact, the AWS documentation uses this approach in its examples. Unfortunately, they didn’t include instructions for working with modules that are locally installed or for dealing with sourcemaps.

There are several benefits to this approach:

- It’s relatively simple, since it relies on NPM, which is the de facto authority, to determine which files are needed. There is literally no special configuration required. We just zip up whatever NPM installed. You may still configure the build process for a given module, but we don’t care what it does and we don’t try to build anything at all.
- To the extent that NPM represents a standard for Node, our approach is completely standards-based.
- Sourcemaps work properly: if they’re in the files we zip, they’re available to Node, provided we use the `--enable-source-maps` flag, which we do when we run tests or publish the Lambda.
- It works fine with CoffeeScript. Since we don’t care about the build, the original source doesn’t matter.
- While it isn’t exactly _fast_, it isn’t terribly slow either. In fact, I think we can rebuild Atlas based on it.
- We don’t need a bundler at all. Which means we’re entirely free of bundlers, since with use import maps in the Web client. This also means we don’t have to care about what idiosyncratic configuration a bundler needs.

We could speed up the build by using static dependency analysis. However, as is typical of this ecosystem, there does not appear to be a reliable and up-to-date SDA module available. And since there are so many ways to import (or require) files, writing one is non-trivial. In fact, our approach has the benefit of being more reliable than static dependency analysis, in that it cannot get confused unless NPM itself is confused.

For now, I think we reached the _good enough_ threshold while meeting our design goals. Improving it from here would likely take an order of magnitude more effort, on the order of weeks of development to implement correctly. In _Optimizations_, I discuss why some prospective avenues of improvement do not yield much. Again, it’s always possible I missed a trick or two, but the current performance is as good as I could get it without significantly more work.

## The Code

I’m going to walk through the code and discuss the implementation as we go. Again, the basic approach is to rely on what NPM has already installed. We do not query an NPM registry or NPM-based API to get package metadata. We simply look at what NPM installed and zip that up.

Let’s start with the imports:

```coffeescript
import FS from "fs/promises"
import Path from "path"
import { guard } from "./helpers"
import JSZip from "jszip"
import _glob from "glob"
import { log } from "@dashkite/dolores/logger"
```

Most of this is obvious. The only interesting bit here is the use of the `glob` package. There are a number of better glob packages at this point. I originally chose this one because it’s the one that NPM uses and I was hoping that would help me process the `files` property of the `package.json` file consistent with NPM. As it turned out, we didn’t need that, but the bare bones approach of `glob` serves our purposes well enough, so I just kept it.

```coffeescript
Paths =
  package: Path.resolve "package.json"
  zip:
    directory: Path.resolve ".sky", "build"
```

Next, we set up some paths we’re going to need later.

From here, we wrap `glob` with our own glob function that provides exactly the interface we’ll need later:

```coffeescript
glob = ( pattern, path ) ->
  new Promise ( resolve, reject ) ->
    _glob pattern, 
      cwd: path
      nodir: true
      ignore: [
        "node_modules/**/*"
        "package-lock.json"
        "test/**/*"
      ]
      ( error, matches ) ->
        if error? then reject error else resolve matches
```

First, we want the glob to return relative paths to a given root, so that we can generate correct paths for our zip file. Basically, we want a flat `node_modules` structure, whereas in development, NPM uses symlinks and we end up with a tree, so we need to “flatten” the paths, which the relative paths allow us to do. We also don’t want to return directories and we don’t want to accidentally bundle nested `node_modules` directories, the `package-lock.json` file, nor any test code. Finally, since `glob` uses a callback-based interface, we convert that into a promise-based interface.

Next, we have a simple function to concatenate arrays, which we use when building up our list of files.

```coffeescript
cat = ( a, b ) -> [ a..., b... ]
```

We also have this in Joy, but it’s a one liner and I didn’t need Joy otherwise, so I just inlined it.

We also need to be able to read `package.json` files relative to a given path:

```coffeescript
readPackage = ( path ) ->
  JSON.parse await FS.readFile ( Path.join path, "package.json" ), "utf8"
```

Next, we pull in all the files that Node can import:

```coffeescript
findFiles = ( root ) ->
  do ( files = [] ) ->
    for pattern in [ "**/*.js", "**/*.json" ]
      files = cat files, await glob pattern, root
    files
```

This is really two functions in one. First, it adapts our `glob` function to handle multiple patterns. Arguably, I should have just included this in our `glob` wrapper function above. Second, and more importantly, it specifies exactly which files we’re including. In combination with the `ignore` parameter we pass to the underlying `glob` function, we basically pull in all the JavaScript and JSON files that aren’t in a `node_modules` or `test` folder and aren’t the `package-lock.json` file. I’m not entirely certain this is sufficient. At one time, it was common for modules to add support for other file types, but Node deprecated this behavior and it may even be unsupported at this point. In any event, this configuration appears to work, but it’s possible that modules that try to import other types of files won’t work properly, in which case, we’ll want to expand this list or make it configurable.

Next, we finally get into the meat of the processing. The first thing we need to be able to do is to create a representation of a dependency, sufficient for our purposes.

```coffeescript
makeDependency = ( name, paths ) ->
  for path in paths
    try
      root = Path.join path, "node_modules", name
      await readPackage root
      files = await findFiles root
      return { name, root, files }
    catch error
      if error.code != "ENOENT"
        log "zip", "errors", error.message
  throw new Error "could not resolve #{ name }"
```

The core of this code are the lines right after the `try`:

```coffeescript
      root = Path.join path, "node_modules", name
      await readPackage root
      files = await findFiles root
      return { name, root, files }
```

We want to compose a path to a given module, read its `package.json` file, find the files we need to bundle, and return an object that consists of the module name, the path to its location on the filesystem, and its files.

Notice we don’t keep the result of reading its `package.json`: what we’re really doing by attempting to load it is to determine whether it exists within the given path. If not, we’re going to try another one.

That’s why that code is contained within a try-catch block, which, in turn, is contained within a loop. And it’s also why this function takes not just the module name, but a list of paths where we think the module might be.

The reason we need to do this is that we don’t know whether a given module is inside a nested `node_modules` directory or at the top-level. That depends on whether its a dependency of a local module—typically because we’re developing it alongside the Lambda—or not. Effectively, we keep a stack of paths based on where we are in the dependency tree traversal. We know that a given dependency is within _one_ of those paths, exactly because it’s a dependency. So it’s either in its dependent tree, or its dependent, and so on, until we reach the current directory.

If we get an error, we check to see if the error is just a file-not-found error, in which case we ignore it and carry on. If it’s some other kind of error, we log that, but keep trying in the hope that it’s not a terribly serious problem.

```coffeescript
    catch error
      if error.code != "ENOENT"
        log "zip", "errors", error.message
```

If we exit the loop without returning, that means we didn’t find the module. In that case, we throw since that _is_ a pretty serious problem, and we don’t want to just keep churning away, knowing that we will utlimately produce a zip file that’s missing a dependency.

We now come to the dependency traversal itself:

```coffeescript
crawl = ( path, dependencies = {}, paths = []) ->
  paths.push Path.resolve path
  pkg = await readPackage path
  for name, specifier of pkg.dependencies
    unless ( name.startsWith "@aws-sdk/" ) || dependencies[ name ]?
      dependency = await makeDependency name, paths
      dependencies[ name ] = dependency
      await crawl dependency.root, dependencies, paths
  dependencies
```

During the traversal, we’re going to keep track of the dependencies we find, obviously, and the aforementioned stack of paths. We’re going to call this function recursively with those values, which is where we get the stack semantics for the paths. We first push the path we’re going to crawl onto the paths list. Presumably, this path corresponds to a module, so we read its `package.json`. Unlike the `makeDependency` function, here we keep that value, because that’s how we’re going to get the list of this module’s dependencies. We loop through each dependency, ignoring AWS SDK dependencies (because they’re already available within Node Lambdas) and dependencies that we’ve already seen.

We call `makeDependency` for each one, to turn it into an object that contains the information we need to read its source files and add them to the zip later. We add it to our dependencies dictionary and crawl it in turn, passing in the dependencies dictionary and the paths stack. Once we’ve processed all the dependencies, we return the dependencies dictionary as the result. Notice that we don’t use the return value when invoking the function recursively, since the value we passed in has been modified directly as a side-effect of the traversal.

The next few functions are just to help add files to the zip file. First, we have the function that actually does the work:

```coffeescript
addFile = ({ zip, source, target }) ->
  zip.file target, await FS.readFile source, "utf8"
```

We read the source file and add it to the zip. This simple implementation offers the best tradeoff between simplicity and performance. See _Optimizations_ below for more discussion.

Next, we have a convenience wrapper around `join`, so that when there’s no root directory (such as with files in the immediate directory), we don’t get an error:

```coffeescript
join = ( root, path ) ->
  if root?
    Path.join root, path
  else
    path
```

In turn, that’s just a helper for a function that adds a list of files:

```coffeescript
addFiles = ({ zip, source, target, files }) ->
  for file in files
    await addFile {
      zip
      source: join source, file
      target: join target, file
    }
```

Here, `source` and `target` are directories (possibly undefined, which is why we have the `join` helper). The paths in the `files` array are relative paths, which allows to construct the path where the file actually resides and also the path where we want to place it in the zip. Again, recall that we need to flatten the possibly nested structure on the filestystem. In turn, we get the source and target directories from the dependency object.

In summary, we have a function that crawls the dependencies of the module in the current directory and another that allows to us add the files for a given dependency to a zip file. We’re now ready for the main event:

```coffeescript
bundle = ({ name, path }) ->
```

The `bundle` function is what we will call from the `sky:zip` task. It takes the name of a module and the path to the entry file. However, this is the original source file, not the transpiled JavaScript. So we’ll need to massage that path a bit to get the correct entry point:

```coffeescript
  Paths.zip.file = Path.join Paths.zip.directory, "#{ name }.zip"
  Paths.build = Path.resolve "build", "node", Path.dirname path
```

Recall our `Paths` dictionary from earlier: we add some new paths here so we can reference them more easily later. First, obviously we need the zip file, which is in the zip directory, using the name of the Lambda for the file itself. We also take the directory of the entry point and map that to our build directory. This relies on some knowledge of our build process and could be made configurable in the future as a potential improvement.

Next, we initialize the zip file:

```coffeescript
  zip = new JSZip
```

Simple enough. Next, we crawl the dependencies, which we’ve made simple via our `crawl` function:

```coffeescript
  dependencies = await crawl "."
```

For each dependency, we just add its files:

```coffeescript
  for target, dependency of dependencies
    { root, files } = dependency
    await addFiles { zip, source: root, target, files }
```

The module name is the target directory, which may not seem obvious, but just think in terms of the entries in `node_modules` and it makes sense. For scoped modules, this relies on the fact that the path separator is the same as the scope delimeter for a module name, so this wouldn’t work on systems that use a different path separator. We could easily address that by writing another helper that transforms a possibly scoped module name into a path.

We also need to add the files in the immediate directory:

```coffeescript
  await addFiles {
    zip
    source: Paths.build
    files: await glob "**/*.js", Paths.build
  }
```

There’s no target here, which is why we need our `join` wrapper (which, you’ll recall, we use in `addFiles`). Instead, we’re just going to place all these files at the root of the zip file. We also want to add the `package.json`:

```coffeescript
  await addFile {
    zip
    source: Paths.package
    target: "package.json"
  }
```

We could have simply done `**/*.json` as we did for the modules, but, in general, we compile all our JSON into JavaScript anyway, so I didn’t bother. We should probably just modify our glob wrapper to take an array of patterns, which would make it easier. We already filter out `package-lock.json` so that should work fine.

Anyway, we now have everything in the zip, so we need only write it out. This is a two-step process: first, we create a Node Buffer from the zip object:

```coffeescript
  buffer = await zip.generateAsync
    type: "nodebuffer"
    compression: "DEFLATE"
    compressionOptions:
      level: 9
```

We use the highest compression level because that had no noticeable effect on performance and it speeds up the upload by generating a smaller file. Shout out here to the creator of JSZip: it’s refreshing to see a module that just does its job well. I had zero issues with actually building and generating zip files. My only complaint is that it’s missing a pruning function to eliminate empty directories. You’ll see why that’s an issue when we discuss _Optimizations_.

Finally, we write out the zip file:

```coffeescript
  await FS.mkdir Paths.zip.directory, recursive: true
  await FS.writeFile  Paths.zip.file, buffer
```

It’s almost anticlimatic after all of the above.

The rest of the code is just wrapping `bundle` in a task.

## Optimizations

I found it tempting to try and optimize this code. The short version is that there’s no easy way to improve the performance and it’s probably not worth trying. The long version: I identified two main paths for optimizations:

1. Use the SHA hash generated by NPM and stored in the `package-lock.json` file to determine whether a module has changed, and update the zip file “in place.” This should result in only a small number of files being read from the filesystem and fewer zip-related operations.
2. Use static dependency analysis to figure out which files we need. Again, this should result in a much smaller number of file system reads and zip operations.

We can dismiss (2) pretty quickly, since I was unable to find a standalone module that performs reliable static-dependency analysis. There _are_ modules that claim to do it, but they rely on regular expressions or are outdated and don’t handle `import` statements or don’t handle `exports` in `package.json` and so on. I’m 90% confident that static dependency analysis is the main reason that bundlers are so much faster than our approach, so it’s unfortunate that this functionality isn’t available as a standalone module. If that changes, we could potentially take advantage, but I don’t think it’s going to be worthwhile to try and write such a module ourselves, at least for the foreseeable future.

Which leaves (1): I actually implemented this and saw no net performance improvement. The reason is perhaps surprising, or at least it surprised me: removing files that are no longer needed turns out to be tricky to implement because removing a file from the zip doesn’t remove its directory entries. If I ignore this, I did see at 30-40% improvement. Maybe we could just leave the directory entries, since increase in the file size is probably negligible. And it isn’t that difficult to prune the zip file anyway. However, on the whole, this approach to optimization—tracking the hashes, pruning the zip file—introduces a lot of complexity into the implementation. And, since it doesn’t reduce the size of the resulting zip file, the overall performance impact is muted by the time it takes to upload the file anyway. Even without taking that into account, it’s only about 2 seconds for the test project I was using as a benchmark. In the end, I didn’t feel the savings was worth the additional complexity in the implementation.

The current implementation is relatively straightforward: crawl the dependencies, read the corresponding source files, and add them to a zip file. In terms of performance, the real problem is that we’re determining the dependencies based on the `package.json` instead of the source files. However, until there’s an easy way to do that, I think what we have offers the most bang-for-the-buck. And if we _are_ able to eventually crawl the source files directly instead of the package dependencies, we simply replace our `crawl` function and everything else works the same.

## Implications For Atlas

I think we could improve Atlas’ performance considerably by using the same approach we use here. I was never happy with the way Atlas came out because the implementation is complicated. I think we could simplify the implementation considerably as well by using the approach we take for zipping files:

- Basically, we’d build a dependency tree, similar to what we do now, but not flattened yet. We don’t want to flatten it right away because we need to preserve the scopes—recall that import maps allows you to use multiple versions of the same module by scoping when a given version is used.
- We can generate the scopes simply by promoting and/or removing redundant leaf nodes. Given our experience using Atlas, we can probably be a little more liberal with finding entry points.
- We could pull this logic into Atlas, so that the zip task just uses Atlas to obtain a flattened tree, using a flattening “strategy.” The import map strategy would compare versions, returning a partially flattened tree, corresponding to the import map scopes, and the zip strategy would ignores versions, producing a completely flattened tree, which is what we need for the zip file.
- Rather than produce the list of files when we create the dependency, we could introduce dedicated functions for that as well, one for globbing, as we do for zipping, and one producing entry points—which is just a set a globs—which is what we need for import maps.

Given that our zip crawler is less than 40 LOC, and Atlas is more than 600 LOC, I think the advantages in simplicity would be considerable. We’d also simplify the zip implementation since it could use Atlas to produce the tree and file lists and we’d just need to manage the zip file.

There’s also a question of whether it makes sense to use the zip strategy of finding modules in the filesystem or via HTTP. The latter is slower but, with caching, there’s not much difference. In fact, it might even be marginally faster to load via HTTP once everything is cached.