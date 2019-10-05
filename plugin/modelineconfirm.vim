" vim: set sw=4 sts=4 :
" Script:           modelineconfirm.vim
" Author:           Michael Potter <mpotter.dev at googlemail.com>
" Homepage:         http://github.com/michaelpotter/modelineconfirm
" Requires:         Vim 7
" License:          Redistribute under the same terms as Vim itself
" Purpose:          Review and confirm modelines before running them

if &compatible || &modeline == 0 || !has('dialog_con') || v:version < 700 || exists('g:loaded_modelineconfirm')
	finish
endif

let g:loaded_modelineconfirm = 1

if (! exists("g:modelineconfirm_path"))
	let g:modelineconfirm_path = "~/.vim/.modelines"
endif

" make the cache dirs
for f in ['', '/approved', '/any_file', '/denied' ]
	let p = expand(g:modelineconfirm_path) . f
	if ! isdirectory(p)
		call mkdir(p)
	endif
endfor

" some other ideas:
" - keep a modeline 'db'. If this exact ml was approved before, even in anothr
"	   file, just run it. Good for large codebases w/ exact modelines all
"	   over
fun! Main() abort
	" to fail closed, we'll turn off modeline now, and turn back on
	" if user wants it
	setlocal nomodeline

	let l:modelines = <SID>GetModelines()

	if <SID>ModelinesApproved(l:modelines)
		setlocal modeline
		return
	elseif <SID>FileApproved(l:modelines)
		setlocal modeline
		return
	elseif <SID>FileDenied(l:modelines)
		return
	else
		call <SID>ReviewModelines(l:modelines)
	endif
endfun

" if these modelines were approved for the cur file
fun! <SID>FileApproved(modelines)
	let cf = <SID>GetCacheFile('approved')
	return filereadable(cf) && <SID>CompareCache(a:modelines, cf)
endfun

" if these modelines were denied for the cur file
fun! <SID>FileDenied(modelines)
	let cf = <SID>GetCacheFile('denied')
	return filereadable(cf) && <SID>CompareCache(a:modelines, cf)
endfun

" if these modelines were approved for ANY file
fun! <SID>ModelinesApproved(modelines)
	for l:ml in values(a:modelines)
		if ! <SID>CheckModeline(l:ml)
			return 0
		endif
	endfor
	return 1
endfun

" check if this modeline is approved for any file
fun! <SID>CheckModeline(modeline)
	let l:ml = <SID>ConvertModeline(a:modeline)
	return filereadable(expand(g:modelineconfirm_path) .  '/any_file/' . l:ml)
endfun

" present the modelines to the user for review.
fun! <SID>ReviewModelines(modelines)
	if len(a:modelines) > 0
		let l:msg = "found new modelines in this file. Would you like to run them?\n"
		for l:ln in keys(a:modelines)
			let l:msg .= 'line   ' . l:ln . ":\n"
			let l:msg .= a:modelines[l:ln] . "\n"
		endfor
		let l:choice = confirm(l:msg,"&No\n&Yes\n&Always\nNe&ver\n&quit")
		if l:choice == 2
			setlocal modeline
		elseif l:choice == 3
			call <SID>CacheModelines(a:modelines, "approved")
			call <SID>DeCacheModelines(a:modelines, "denied")
			call <SID>ApproveForAll(a:modelines)
			setlocal modeline
		elseif l:choice == 4
			call <SID>CacheModelines(a:modelines, "denied")
			call <SID>DeCacheModelines(a:modelines, "approved")
		elseif l:choice == 5
			quit
		endif
	endif
endfun


" returns a map containing modelines found in the file
" the map is empty if none are found
" key is the line number
" val is the line text
fun! <SID>GetModelines()
	let l:modelines = {}
	let l:upper_range = range(1, &modelines)
	let l:lower_range = range(line('$') - &modelines + 1, line('$'))
	for l:line in l:upper_range + l:lower_range
		if <SID>IsModeline(l:line)
			let l:modelines[l:line] = getline(l:line)
		endif
	endfor
	return l:modelines
endfun


" returns true if the given line number looks like a modeline
" see help modeline
" going with a very wide regex to reduce missed modelines
fun! <SID>IsModeline(linenu)
	return -1  !=  match(getline(a:linenu), '\v(vi|ex|[v|V]im((<|\=|>)?[0-9]+)?):')
endfun


" approves the given modelines for all files
fun! <SID>ApproveForAll(modelines)
	for ml in values(a:modelines)
		let ml = <SID>ConvertModeline(ml)
		let f = expand(g:modelineconfirm_path) .  '/any_file/' . ml
		call writefile([''], f)
	endfor
endfun

" caches the given modelines as either approved or denied
" status must be either 'approved' or 'denied'
fun! <SID>CacheModelines(modelines, status)
	call writefile(values(a:modelines), <SID>GetCacheFile(a:status))
endfun

" decaches the given modelines
" removes the appropriate cachefile
" status must be either 'approved' or 'denied'
fun! <SID>DeCacheModelines(modelines, status)
	if filereadable(<SID>GetCacheFile(a:status))
		call delete(<SID>GetCacheFile(a:status))
	endif
endfun

" Compares the given modelines with those found in the cachefile
" returns true if they are the same
fun! <SID>CompareCache(modelines, cachefile)
	let l:cached = readfile(a:cachefile)
	return s:compareLists(l:cached, values(a:modelines))
endfun

" compares two lists for equality
fun s:compareLists(l1, l2)
	let l1 = sort(a:l1)
	let l2 = sort(a:l2)
	if len(l1) != len(l2)
		return v:false
	endif
	for i in range(len(l1))
		if l1[i] != l2[i]
			return v:false
		endif
	endfor
	return v:true
endfun

" returns path of the cache file for %
" takes status: (approved|denied)
fun! <SID>GetCacheFile(status)
	let l:file = <SID>ConvertFilepath(expand('%'))
	return expand(g:modelineconfirm_path . '/' . a:status . '/' . l:file)
endfun

" converts the filepath to a string that can be saved as a filename
fun! <SID>ConvertFilepath(fpath)
	return fnamemodify(a:fpath, ':p:gs,/,%,')
endfun

" converts the modeline to a string that can be saved as a filename
fun! <SID>ConvertModeline(ml)
	return fnamemodify(a:ml, ':gs,/,%,')
endfun


command ModelineConfirm :call <SID>ReviewModelines(<SID>GetModelines())
aug ModelineConfirm
	au!
	au BufRead,StdinReadPost * :call Main()
aug END
" vim: set ft=java ts=91 :
