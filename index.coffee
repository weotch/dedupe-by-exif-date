# Deps
yargs = require 'yargs'
chalk = require 'chalk'
exiftool = require('exiftool-vendored').exiftool
glob = require 'glob'
mysql = require 'mysql2/promise'
{ renameSync, statSync, existsSync } = require 'fs'

# Global vars
db = null

# Entry point
handler = ({ keep, remove, trash }) ->
	console.log chalk.magenta "Starting –––––––––––––––––––––––––––––––––––––––––"
	db = await connectToDb()
	await indexDir keep
	await indexDir remove
	await dedupe keep, remove, trash
		
# Create DB connection
connectToDb = -> mysql.createConnection
	host: '127.0.0.1'
	user: 'root'
	database: 'dedupe-by-exif-date'
	# debug: true

# Index a directory of media
indexDir = (dir) ->
	console.log chalk.yellow "Indexing #{chalk.white(dir)}"
	files = await listFiles dir
	for file, i in files
		console.log chalk.green "Processing #{i+1}/#{files.length}: 
			#{chalk.white.dim(file)}"
		
		# Check if already in the database
		[ rows ] = await db.query 'SELECT * FROM files WHERE file = ?', file
		if rows.length
			console.log chalk.green.dim "- Skipping, created is #{rows[0].created}"
			continue
		
		# Get the creation time
		tags = await exiftool.read file
		if (date = tags.CreateDate || tags.ModifyDate) and (created = getTime date)
		then console.log chalk.green.dim "- Created: #{created}"
		else
			console.log chalk.red "- No date found"
			await logError file, 'No date', JSON.stringify tags
			continue
		
		# Add it to database
		await db.query 'INSERT INTO files SET file = ?, created = ?', 
		[file, created]

# Get all files in a dir recursively
listFiles = (dir) -> new Promise (resolve) -> 
	glob "#{dir}/**/*", (er, files) -> resolve files
	
# Manually create a JS Date and return the timestamp
# https://github.com/mceachen/exiftool-vendored.js/issues/46
getTime = (d) ->
	date = new Date d.year, d.month - 1, d.day, d.hour, d.minute, d.second, 
		d.millisecond
	date.getTime()
	
# Loop through all the indexed files from keep and find instances in remove with
# the same created date.  Move the 'remove' versions to the trash
dedupe = (keep, remove, trash) ->
	
	# Get all keep records
	[keeps] = await db.query 'SELECT * FROM files WHERE file LIKE ?', "#{keep}%"
	console.log chalk.yellow "Deduping #{chalk.white("#{keeps.length} files")}"
	for keep, i in keeps
		console.log chalk.green "Deduping #{i+1}/#{keeps.length}: 
			#{chalk.white.dim(keep.file)}"
		
		# Verify the file still exists.  It may not in the case that a previous
		# match was for the same dir path and this file was smaller than another
		unless existsSync keep.file
			console.log chalk.green.dim '- No longer exists'
			continue
		
		# Make sure file has IMG_ in it, I had issues when searching my the archive
		# for the oldest files with non-dupe files that had the same name
		unless keep.file.indexOf('IMG_') > 0
			console.log chalk.green.dim '- Non-"IMG_"'
			continue
		
		# Get all the remove records with the same timestmap
		[matches] = await db.query 'SELECT * FROM files WHERE id != ? && created = ?', 
			[keep.id, keep.created]
		
		# Move matches to the trash
		if matches.length > 0
			console.log chalk.green.dim "- Found #{matches.length} match(es)"
			for match in matches
				trashPath = match.file.replace remove, trash
				
				# If the keep and remove paths are the same, keep the larger file.
				if keep.file.indexOf(remove) == match.file.indexOf(remove) and
				statSync(match.file)['size'] > statSync(keep.file)['size']
					console.log chalk.green.dim "- Match was bigger, swappping"
					temp = keep
					keep = match
					match = temp
				
				# Move the "match"
				console.log chalk.green.dim "- Moving #{match.file}"
				console.log chalk.green.dim "- To #{trashPath}"
				renameSync match.file, trashPath
				
				# Keep the DB up to date
				console.log chalk.green.dim "- Deleting `#{match.id}` from DB"
				await db.query 'DELETE FROM files WHERE id = ?', match.id
		
		# Else, no matches found
		else console.log chalk.green.dim "- Found 0 matches, skipping"

# Log an error
logError = (file, type, extra) ->
	db.query 'INSERT INTO errors SET file = ?, type = ?, extra = ?', 
		[file, type, extra]

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