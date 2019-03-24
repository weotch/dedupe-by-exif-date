# Deps
yargs = require 'yargs'
chalk = require 'chalk'
exiftool = require('exiftool-vendored').exiftool
glob = require 'glob'

# Entry point
handler = ({ keep, remove, trash }) ->
	console.log chalk.magenta "Starting –––––––––––––––––––––––––––––––––––––––––"
	await indexDir keep
	await indexDir remove
		
# Index a directory of media
indexDir = (dir) ->
	console.log chalk.yellow "Indexing: #{chalk.white(dir)}"
	for file in await listFiles dir
		console.log "Processing: #{file}"
		tags = await exiftool.read file
		created = getTime tags.CreateDate
		console.log "Created at: #{created}"

# Get all files in a dir recursively
listFiles = (dir) -> new Promise (resolve) -> 
	glob "#{dir}/**/*", (er, files) -> resolve files
	
# Manually create a JS Date and return the timestamp
# https://github.com/mceachen/exiftool-vendored.js/issues/46
getTime = (d) ->
	date = new Date d.year, d.month - 1, d.day, d.hour, d.minute, d.second, 
		d.millisecond
	date.getTime() 

# Expose CLI interface
yargs
	.command '* <keep> <remove> <trash>',
		'Look for duplicates of media from the "keep" dir in the "remove" dir and 
			move them to the "trash" dir.',
		(yargs) ->
			yargs.positional 'keep',
				describe: 'The directory of media to keep'
				type: 'string'
			yargs.positional 'remove',
				describe: 'The directory of media whose duplicates will be removed'
				type: 'string'
			yargs.positional 'trash',
				describe: 'The directory that removed media will be moved to'
				type: 'string'
		, (handler)
	.help()
	.argv