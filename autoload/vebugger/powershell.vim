let s:SYS = SpaceVim#api#import('system')


function! vebugger#powershell#start(entryFile,args)
	let l:debuggerExe = 'powershell'
    let l:debugger=vebugger#std#startDebugger(shellescape(l:debuggerExe) . vebugger#util#commandLineArgsForProgram(a:args))

	let l:debugger.state.powershell={}

	if !has('win32')
		call vebugger#std#openShellBuffer(l:debugger)
	endif

	call l:debugger.writeLine('Get-PSBreakpoint | Remove-PSBreakpoint')
	call l:debugger.writeLine('Set-PSBreakpoint -Line 1 -Script ' . vebugger#util#WinShellSlash(a:entryFile))
	call l:debugger.writeLine(vebugger#util#WinShellSlash(a:entryFile))

	call l:debugger.addReadHandler(function('vebugger#powershell#_readProgramOutput'))
	call l:debugger.addReadHandler(function('vebugger#powershell#_readWhere'))
	call l:debugger.addReadHandler(function('vebugger#powershell#_readFinish'))
	call l:debugger.addReadHandler(function('vebugger#powershell#_readEvaluatedExpressions'))

	call l:debugger.setWriteHandler('std','flow',function('vebugger#powershell#_writeFlow'))
	call l:debugger.setWriteHandler('std','breakpoints',function('vebugger#powershell#_writeBreakpoints'))
	call l:debugger.setWriteHandler('std','closeDebugger',function('vebugger#powershell#_closeDebugger'))
	call l:debugger.setWriteHandler('std','evaluateExpressions',function('vebugger#powershell#_requestEvaluateExpression'))
	call l:debugger.setWriteHandler('std','executeStatements',function('vebugger#powershell#_executeStatements'))
	call l:debugger.setWriteHandler('std','removeAfterDisplayed',function('vebugger#powershell#_removeAfterDisplayed'))

	call l:debugger.generateWriteActionsFromTemplate()

	call l:debugger.std_addAllBreakpointActions(g:vebugger_breakpoints)

	return l:debugger
endfunction

function! vebugger#powershell#_readProgramOutput(pipeName,line,readResult,debugger) dict
	if 'out'==a:pipeName
		if a:line=~"\\V\<C-[>[C" " After executing commands this seems to get appended...
			let self.programOutputMode=1
			return
		endif
		if a:line=~'\v^\>'
					\||a:line=~'\V\^[DBG]' "We don't want to print this particular line...
					\||a:line=='The program finished and will be restarted'
			let self.programOutputMode=0
		endif
		if get(self,'programOutputMode')
			let a:readResult.std.programOutput={'line':a:line}
		endif
		if a:line=~'\v^\(Pdb\) (n|s|r|cont)'
			let self.programOutputMode=1
		endif
	else
		let a:readResult.std.programOutput={'line':a:line}
	endif
endfunction

function! vebugger#powershell#_readWhere(pipeName,line,readResult,debugger)
	if 'out'==a:pipeName
        " in doc it is:
        " At PS /home/jen/debug/test.ps1:6 char:1
        if s:SYS.isWindows
            " At C:\Users\wsdjeg\Desktop\test.ps1:1 char:1 
            let l:matches=matchstr(a:line,'\(At\s\+\)\@<=.*')
        else
            let l:matches=matchstr(a:line,'\(At PS\s\+\)\@<=.*')
        endif

		if !empty(l:matches)
			let l:file=vebugger#util#WinShellSlash(join(split(l:matches, ':')[:-3], ':'))
			if !empty(glob(l:file))
                let l:line = split(l:matches, ':')[-2][:-6]
				let a:readResult.std.location={
							\'file':(l:file),
							\'line':(l:line)}
			endif
		endif
	endif
endfunction

function! vebugger#powershell#_readFinish(pipeName,line,readResult,debugger)
	if a:line=='The program finished and will be restarted'
		let a:readResult.std.programFinish={'finish':1}
	endif
endfunction

function! vebugger#powershell#_writeFlow(writeAction,debugger)
	if 'stepin'==a:writeAction
		call a:debugger.writeLine('stepInto')
	elseif 'stepover'==a:writeAction
		call a:debugger.writeLine('stepOver')
	elseif 'stepout'==a:writeAction
		call a:debugger.writeLine('stepOut')
	elseif 'continue'==a:writeAction
		call a:debugger.writeLine('continue')
	endif
endfunction

function! vebugger#powershell#_closeDebugger(writeAction,debugger)
	call a:debugger.writeLine('quit')
endfunction

function! vebugger#powershell#_writeBreakpoints(writeAction,debugger)
	for l:breakpoint in a:writeAction
		if 'add'==(l:breakpoint.action)
			call a:debugger.writeLine('Set-PSBreakpoint -Line ' . l:breakpoint.line . ' -Script ' . fnameescape(fnamemodify(l:breakpoint.file,':p')))
		elseif 'remove'==l:breakpoint.action
			call a:debugger.writeLine('Remove-PSBreakpoint -Line ' . l:breakpoint.line . ' -Script ' . fnameescape(fnamemodify(l:breakpoint.file,':p')))
		endif
	endfor
endfunction

function! vebugger#powershell#_requestEvaluateExpression(writeAction,debugger)
	for l:evalAction in a:writeAction
		call a:debugger.writeLine('p '.l:evalAction.expression)
	endfor
endfunction

function! vebugger#powershell#_executeStatements(writeAction,debugger)
	for l:evalAction in a:writeAction
		if has_key(l:evalAction,'statement')
			call a:debugger.writeLine('!'.l:evalAction.statement)
		endif
	endfor
endfunction

function! vebugger#powershell#_readEvaluatedExpressions(pipeName,line,readResult,debugger) dict
	if 'out'==a:pipeName
		if has_key(self,'expression') "Reading the actual value to print
			let l:value=a:line
			let a:readResult.std.evaluatedExpression={
						\'expression':(self.expression),
						\'value':(l:value)}
			"Reset the state
			unlet self.expression
		else "Check if the next line is the eval result
			let l:matches=matchlist(a:line,'\v^\(Pdb\) p (.*)$')
			if 1<len(l:matches)
				let self.expression=l:matches[1]
			endif
		endif
	endif
endfunction

function! vebugger#powershell#_removeAfterDisplayed(writeAction,debugger)
	for l:removeAction in a:writeAction
		if has_key(l:removeAction,'id')
			"call a:debugger.writeLine('undisplay '.l:removeAction.id)
		endif
	endfor
endfunction

