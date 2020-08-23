const fs = require('fs-extra')

let copiedCount = 0

let fileNames = [
	'/ffmpeg-worker.js',
]

for (let fileName of fileNames) {
	let filePath = __dirname + '/' + fileName

	if (!fs.pathExistsSync(filePath)) {
		continue
	}

	if (fileName.endsWith('.js')) {
		let text = fs.readFileSync(filePath, {encoding: 'utf8'})
		let optionVariableName = text.match(/function \w+\((\w+)\)/)[1]
		
		text = text.replace(/\.open\("GET",(\w+),!1\)/g, `.open("GET",${optionVariableName}.wasm_url||$1,!1)`)
			.replace(/(postMessage\(\{type:"run"\}\);var \w+=\{\};\w+\.)\w+(=\w+;)/, '$1wasm_url$2')
			
		fs.writeFileSync(filePath, text)
	}

	copiedCount++
}

console.log(`${copiedCount} files fixed!`)