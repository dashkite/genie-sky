# Implementation Guide

*Zip Bundling For AWS Lambda*

**Dan Yoder**

A fair amount of effort has gone into the implementation of our zip bundler for AWS Lambdas. This document is intended to help ensure that we don’t replicate any of that effort again later.

## Background

In principle, what we want seems simple: to use sourcemaps when debugging AWS Lambda functions. In practice, this turns out to be difficult, probably because we’re using CoffeeScript and we’re generating sourcemaps when we build. Build tools like Webpack and ESBuild seem to assume that they’re responsible for generating sourcemaps. Some tools offer a variety of configuration options and it’s possible that there’s a way to do handle this scenario. It’s also possible to configure the build process so that it’s handled by the bundler. However, all of these approaches rely on non-standard, idiosyncratic interfaces that require that our modules be configured to suit the bundler. It’s fair to say that we had a second, tacit objective: to rely on simple and standard configurations for our build process.

Even if we try to stick to standards—including de facto standards within the Node ecosystem—keeping it simple remains a challenge. Modules may use a variety of different ways to tell a package manager which files to include in a module, each of which may involve numerous rules. To provide just one example, NPM’s `package.json` has `main`, `modules`, and sometimes `browser` to indicate entry points, the `files` property that provides a Git-ignore style list of files and directories, and an `exports` property to support ESM. A given module may use any or all of these. What’s more, there’s no module—at least that I could find—that encapsulates all this complexity in such a way that you can simply point at a module and say, please give me all the files this module might use. Which is surprising, given the number of bundlers out there—Webpack, Parcel, Rollup, SnowPack, ESBuild, among others—each of which apparently implements this functionality without making it available independent of the bundler itself.

I probably spent the bulk of the time researching ways to configure bundlers to do what we wanted and trying to bootstrap using existing libraries, mostly because it seemed implausible that there wasn’t a straightforward way to do what we wanted. This effort did not yield any useful result. Of course, I probably overlooked something, but the very fact that I wasn’t able to find a solution reasonably quickly is the real problem. Even if we found a winning configuration, it would be brittle and difficult to reason about. And it’s equally difficult to build a solution because, again, the building blocks are coupled to the bundlers and package managers. It shouldn’t be this way, and there’s a whole discussion we could have about how badly this ecosystem is broken, but, for our purposes here, all we need to say is to approach with caution. Hopefully, the approach we’re using will serve us for the foreseeable future.

Another approach I tried and discarded was to use Atlas. This worked but was slow because Atlas is slow. Atlas is slow because it assumes that it needs to load everything from the Web. See _Implications For Atlas_ below.

### The Breakthrough

Initially, we proved that our approach could work by using the local filesystem as a limited replica of NPM: we assume that you’ve run `npm install` for any local dependencies and, thus, we can use the installed files to figure out which files we need. From there, we place them in a zip file instead of bundling them. The [results of this effort](https://github.com/dashkite/sky-presets/blob/e61071339d6a0fd98f16b6182cd8cb4f67f9f699/src/zip.coffee) are documented in [an earlier version of this document](https://github.com/dashkite/sky-presets/blob/e61071339d6a0fd98f16b6182cd8cb4f67f9f699/docs/zip.md#the-breakthrough). Unfortunately, the end result was slower than we would have liked. One way to speed it up was to use a static-dependency analysis tool:

> [We could use] static dependency analysis to figure out which files we need. Again, this should result in a much smaller number of file system reads and zip operations.
>
> We can dismiss [this idea] pretty quickly, since I was unable to find a standalone module that performs reliable static-dependency analysis.

However, as it turns out, esbuild is so fast that we can discard the bundle it produces and use the metadata instead, which includes a list of the files it bundled. From there, we have to infer the target path in the zip file and the location of the `package.json`, but we can basically retrofit esbuild to do the SDA.

This worked: our build is now _faster_ than it would be with any bundler, except obviously esbuild. We can typically produce a zip file in well under a second. And since the zip file is smaller—because it includes fewer files—the upload time is also reduced and is now comparable to using a bundler. For example, for the Load Media lambda, the total time using the previous approach was roughly 15 seconds. Piggybacking off esbuild reduced that to 5 seconds.

## The Code

I’m going to walk through the code and discuss the implementation as we go. 

Let’s start with the imports:

```coffeescript
import FS from "fs/promises"
import Path from "path"
import { guard } from "./helpers"
import JSZip from "jszip"
import { log } from "@dashkite/dolores/logger"
import esbuild from "esbuild"
```

Most of this is obvious, so let’s move along. We set up some helpers for dealing with paths.

```coffeescript
normalize = ( path ) ->
  if path[0] == "/" || path[0] == "."
    path
  else
    "./#{ path }"
  
split = ( path ) -> path.split Path.sep

join = ( items ) -> Path.join items...
```

Next, we have a way to read files, ensuring we never read them more than once:

```coffeescript
cache = {}

read = ( path ) ->
  cache[ path ] ?= await do ->
    FS.readFile path, "utf8"
```

We wrap `read` to create a function to check for the existence of a file:

```coffeescript
exists = ( path ) ->
  try
    await read path
    true
  catch
    false
```

We do that so that we can quickly check for the existence of `package.json` files, which is what `choose` does. Given a list of paths, it returns the one that has a `package.json`, which means it’s a module root.

```coffeescript
choose = ( paths ) ->
  for path in paths
    if await exists Path.join path, "package.json"
      return path
  null
```

We should probably cache the existence checks as well, since the `read` cache only keeps the files that are actually there. But that would probably be a relatively minor win, given how fast this runs already.

Next, we have a simple file that gets us package info:

```coffeescript
getPackage = ( root ) ->
  source = Path.join root, "package.json"
  text = await read source
  data = JSON.parse text
  { source, data }
```

All this is to set up this next function, which is the workhorse for this implementation.

```coffeescript
getModule = ( source ) ->
```

This is a unwieldy function so I’ll go through it in parts. We should probably break this into smaller functions, but this is what’s currenlty implemented.

```coffeescript
  local = false
  items = split source
  i = items.lastIndexOf "node_modules"
```

We need to deal with the path as an array of path components. Among other things, this allows to find the last `node_modules` directory in the path, if any, which will allow us determine to which module a given file belongs:

```coffeescript
  root = if i > 0
    if items[ i + 1 ][0] == "@"
      join items[0..( i + 2 )]
    else
      join items[0..( i + 1 )]
```

This says that if the next path component starts with an `@`, we know this is a scoped package, so the package root will actually be the next directory down. Otherwise, it’s the one right after `node_modules`.

For example, if we have:

`./node_modules/@foo/bar/build/node/src/index.js`

we know the module root is `./node_modules/@foo/bar`. Whereas for:

`./node_modules/foo/build/node/src/index.js`

we know it’s simply `./node_modules/@foo/bar`.

The `else` branch handles the case where there’s no `node_modules`:

```coffeescript
  else
    local = true
    await choose [
      join items[0..1]
      items[0]
      "."
      join items[0..2]
    ]
```

In this case, we know this is a module in local development and so it must be in either the current module or a module reference by the first two path components. For example, given a file in the current module:

`./build/node/src/index.js`

obviously the module root is `.`. On the other hand, given:

`../media-type/build/node/src/index.js`

we know the root is `../media-type`, which is the first two path components.

It’s possible to get a path like:

`../../pandastrike/panda-confidential/build/node/src/index.js`

which the last case handles, but reall we should probably just expand the path until we find a `package.json`. We would lose the prioritization of the paths though, but maybe there’s a way to preserve that.

Anyway, at this point we have the module root for a given file. So let’s get the corresponding package:

```coffeescript
  _package = await getPackage root
```

Armed with the package, we compute the target path for the file and its `package.json` file so we can include them in the zip file later. The computation of this depends on whether we’re in the current module or not. If so, we compute the path relative to the build path. Although `Paths.build` isn’t defined yet, it will be by the time we call this function. If we’re not in the current module, we want to place this the zip archive’s `node_modules` folder, and we compute the paths relative to the module root, inserting the module name into the path, based on the name given in the `package.json` file.

```coffeescript
  if root == "."
    target = Path.relative Paths.build, source
    _package.target = "package.json"
  else
    target = Path.join "node_modules",
      _package.data.name,
      Path.relative root, source
    _package.target = Path.join "node_modules",
      _package.data.name,
      "package.json"

```

Technically, we should split the name into path components before joining them.

We now have all the metadata we need for the file, so we return that:

```coffeescript
{ source, root, local, target, package: _package }
```

Next, we define a helper that will use this metadata to add a file to a zip archive:

```coffeescript
addFile = ({ zip, source, target }) ->
  zip.file target, await read source
```

For the `package.json` files, we’ll end up getting them from cache, since we’ve already read them.

We also need a place to keep track of the paths we’re using:

```coffeescript
Paths =
  zip:
    directory: Path.resolve ".sky", "build"
```

We’re now ready for the main event:

```coffeescript
bundle = ({ name, path }) ->
```

The `bundle` function is what we will call from the `sky:zip` task. It takes the name of a module and the path to the entry file. However, this is the original source file, not the transpiled JavaScript. So we’ll need to massage that path a bit to get the correct entry point:

```coffeescript
  Paths.zip.file = Path.join Paths.zip.directory, "#{ name }.zip"
  Paths.build = Path.resolve "build", "node", Path.dirname path
```

Recall our `Paths` dictionary from earlier: we add some new paths here so we can reference them more easily later. First, obviously we need the zip file, which is in the zip directory, using the name of the Lambda for the file itself. We also take the directory of the entry point and map that to our build directory. This relies on some knowledge of our build process and could be made configurable in the future as a potential improvement.

We’re also going to need a Zip archive, obviously:

```coffeescript
  zip = new JSZip
```

We perform our SDA by piggybacking off esbuild:

```coffeescript
  { metafile } = await esbuild.build
    entryPoints: [ "build/node/src/index.js" ]
    bundle: true
    sourcemap: false
    platform: "node"
    conditions: [ "node" ]
    outfile: "/dev/null"
    external: [ "@aws-sdk/*" ]
    metafile: true
```

We don’t need sourcemaps—we already have them—so we turn those off. We also send the output to `/dev/null` since we don’t care about it. All we want is the metadata, which is returned as the `metafile` property.

We iterate through the files it returns and prepare them for archival:

```coffeescript
  files = {}
  for source, _ of metafile.inputs
    m = await getModule source
    files[ m.target ] = { source, m... }
    files[ m.package.source ] ?= m.package
```

`getModule` is a misnomer, since what we’re really doing is getting the metadata associated with the file and computing the relative paths that we’ll use when adding to the archive. So that should probably be called `getFileMetadata` or something. We place these objects into a `files` dictionary to ensure that we don’t try to add multiple copies to the archive, which would pointlessly slow things down. Consequently, we only keep one version of a module—because they will share the same target paths—and we may include extraneous files. There is presently no means to select which version of a module is prioritized or to include two versions (by using nested `node_modules` directories).

We now have all the files, so we add them to the zip archive:

```coffeescript
  await Promise.all do ->
    for { source, target } in Object.values files
      addFile { zip, source, target }
```

The `Promise.all` bit here probably doesn’t make much difference, but it doesn’t hurt either. Recall that `addFile` reads the file that its adding from the filesystem, and `read`, in turn, attempts to read from a cached version if possible.

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

## Issues

- We only keep one version of a module—because they will share the same target paths—and we may include extraneous files. There is presently no means to select which version of a module is prioritized or to include two versions (by using nested `node_modules` directories).

## Implications For Atlas

I think we could improve Atlas’ performance considerably by using the same approach we use here. I was never happy with the way Atlas came out because the implementation seems unnecessarily complicated. We could also slim down the import map considerably. We could work backward from the file list we build for the archive into an import map. Crucially, esbuild includes in its metadata information about dependent files. If we include this, we can also infer dependent modules (since we’ve already managed to link the file to the module in the zip process).

We still need to infer the scoping and the import paths. I think this might be pretty simple, since we already know the path that was used for the import. We could just scope everything and then promote scoped modules when there’s no conflict, which basically just trims down the file so we don’t have the same files in two different scopes. Presuming that the import paths are as straightforward as I think they are, this would end up being wildly simpler than what we currently have. In turn, solving the scoping problem gives us the map we need to generate nested `node_modules` directories when we zip, since the scoping corresponds to the nesting.