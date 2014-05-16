
"Shamefully stolen from http://stackoverflow.com/a/6271254/794380
function! vebugger#util#get_visual_selection()
	" Why is this not a built-in Vim script function?!
	let [lnum1, col1] = getpos("'<")[1:2]
	let [lnum2, col2] = getpos("'>")[1:2]
	let lines = getline(lnum1, lnum2)
	let lines[-1] = lines[-1][: col2 - (&selection == 'inclusive' ? 1 : 2)]
	let lines[0] = lines[0][col1 - 1:]
	return join(lines, "\n")
endfunction

function! vebugger#util#selectProcessOfFile(ofFile)
	let l:fileName=fnamemodify(a:ofFile,':t')
	let l:resultLines=split(vimproc#system('ps -o pid,user,comm,start,state,tt -C '.fnameescape(l:fileName)),'\r\n\|\n\|\r')
	if len(l:resultLines)<=1
		throw 'No matching process found'
	endif
	if &lines<len(l:resultLines)
		throw 'Too many matching processes found'
	endif
	let l:resultLines[0]='     '.l:resultLines[0]
	for l:i in range(1,len(l:resultLines)-1)
		let l:resultLines[l:i]=repeat(' ',3-len(l:i)).l:i.') '.(l:resultLines[l:i])
	endfor
	let l:chosenId=inputlist(l:resultLines)
	if l:chosenId<1
				\|| len(l:resultLines)<=l:chosenId
		return 0
	endif
	let l:chosenLine=l:resultLines[l:chosenId]
	return str2nr(matchlist(l:chosenLine,'\v^\s*\d+\)\s+(\d+)')[1])
endfunction
