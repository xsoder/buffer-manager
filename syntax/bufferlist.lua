vim.cmd([[
  syntax match BufferListNumber /^\s*\d\+:/
  syntax match BufferListModified /\[+\]/
  syntax match BufferListCurrent /\*$/

  highlight default link BufferListNumber Number
  highlight default link BufferListModified WarningMsg
  highlight default link BufferListCurrent SpecialKey
]])
