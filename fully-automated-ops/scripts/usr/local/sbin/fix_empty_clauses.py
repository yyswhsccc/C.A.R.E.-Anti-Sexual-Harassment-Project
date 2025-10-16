#!/usr/bin/env python3
# -*- coding: utf-8 -*-
import sys, re, os, shutil

def is_blank_or_comment(s):
    t=s.strip()
    return (t=='' or t.startswith('#'))

def indent(s):
    return len(s) - len(s.lstrip(' '))

def needs_pass(lines, i):
    base = indent(lines[i])
    j = i+1
    # 跳过空行/注释
    while j < len(lines) and is_blank_or_comment(lines[j]):
        j += 1
    # 到文件末尾 => 需要 pass
    if j >= len(lines):
        return True
    t = lines[j].lstrip()
    # 下一行缩进不更深 => 需要 pass
    if indent(lines[j]) <= base:
        return True
    # 下一条就是 except/else/finally => 需要 pass
    if t.startswith(('except', 'finally:', 'else:')):
        return True
    return False

def process(path):
    with open(path,'r',encoding='utf-8') as f:
        lines=f.readlines()
    changed=False; i=0
    while i < len(lines):
        t = lines[i].lstrip()
        if re.match(r'(try:|except\b.*:|finally:)', t):
            if needs_pass(lines, i):
                lines.insert(i+1, ' '*(indent(lines[i])+4)+'pass\n')
                changed=True; i += 1
        i += 1
    if changed:
        os.makedirs('/root/py_fix_backup', exist_ok=True)
        shutil.copy2(path, '/root/py_fix_backup/'+path.lstrip('/').replace('/','__')+'.orig')
        with open(path,'w',encoding='utf-8') as f:
            f.writelines(lines)
        print('[FIXED]', path)
    else:
        print('[OK]', path)

if __name__=='__main__':
    for p in sys.argv[1:]:
        process(p)
