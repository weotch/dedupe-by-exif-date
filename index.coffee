# Deps
yargs = require 'yargs'
chalk = require 'chalk'
exiftool = require('exiftool-vendored').exiftool
glob = require 'glob'
mysql = require 'mysql2/promise'
{ renameSync } = require 'fs'

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
		if date = tags.CreateDate || tags.ModifyDate
			created = getTime date
			console.log chalk.green.dim "- Created: #{created}"
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
		
		# Get all the remove records with the same timestmap
		[removes] = await db.query 'SELECT * FROM files WHERE id != ? && created = ?', 
			[keep.id, keep.created]
		
		# If only one match, move it
		if removes.length == 1
			removePath = removes[0].file
			trashPath = removePath.replace remove, trash
			console.log chalk.green.dim "- Found 1 match"
			console.log chalk.green.dim "- Moving #{removePath}"
			console.log chalk.green.dim "- To #{trashPath}"
			renameSync removePath, trashPath
			
			# Keep the DB up to date
			console.log chalk.green.dim "- Deleting `#{removes[0].id}` from DB"
			await db.query 'DELETE FROM files WHERE id = ?', removes[0].id
		
		# If more than one match, raise an alert about it
		else if removes.length > 1
			console.log chalk.red "- Found #{removes.length} matches, help!"
			matches = removes.map (remove) -> remove.file
			await logError keep.file, 'Multiple matches', matches.join(',')
		
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