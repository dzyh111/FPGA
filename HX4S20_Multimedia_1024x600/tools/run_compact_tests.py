from pathlib import Path
import subprocess,sys,json,re,time,hashlib
root=Path(__file__).resolve().parents[1]
out=root/'sim/compact_tests';out.mkdir(exist_ok=True)
bins=Path('C:/Users/dyzh/Documents/ChatGPT/FPGA/tools/iverilog-portable/bin')
tests=sys.argv[1:] or ['tb_playlist','tb_wav_reader','tb_heritage_audio_reader','tb_bmp_ranges','tb_cover_reader','tb_gallery_pack_formats','tb_lba_share_equivalence','tb_zoom_borrow_equivalence']
rows=[]
for top in tests:
 folder='sim/compact_tests' if top in ['tb_lba_share_equivalence','tb_zoom_borrow_equivalence'] else 'sim'
 ext='sv' if (root/f'{folder}/{top}.sv').exists() else 'v'
 cmd=[str(bins/'iverilog.exe'),'-g2012','-I','.','-I','rtl','-y','rtl','-y','sim','-y','user_source/hdl_source/SD','-y','user_source/hdl_source/IP','-s',top,'-o',str(out/(top+'.vvp')),f'{folder}/{top}.{ext}']
 if top=='tb_lba_share_equivalence':cmd.append('sim/compact_tests/bmp_read_reference.v')
 if top=='tb_zoom_borrow_equivalence':cmd.append('sim/compact_tests/video_zoom_rgb565_reference.v')
 start=time.monotonic();cp=subprocess.run(cmd,cwd=root,capture_output=True,text=True,errors='replace')
 (out/(top+'_compile.log')).write_text(cp.stdout+cp.stderr,encoding='utf-8')
 assert cp.returncode==0,cp.stdout+cp.stderr
 args=[str(bins/'vvp.exe'),'-i',str(out/(top+'.vvp'))]
 # Full existing SUB1/SUB2 pack scenarios, not the old tag-change subset.
 with (out/(top+'.log')).open('w',encoding='utf-8') as log:
  cp=subprocess.run(args,cwd=root,stdout=log,stderr=subprocess.STDOUT,timeout=1800)
 text=(out/(top+'.log')).read_text(encoding='utf-8',errors='replace')
 ok=cp.returncode==0 and re.search(r'(?m)^PASS\b',text) and not re.search(r'(?im)^\s*(FATAL:|ERROR:|FAIL\b)',text)
 row={'test':top,'result':'PASS' if ok else 'FAIL','seconds':round(time.monotonic()-start,2),'output':text,'source_sha256':{n:hashlib.sha256((root/n).read_bytes()).hexdigest().upper() for n in ['user_source/hdl_source/SD/bmp_read.v','rtl/video_zoom_rgb565.v']}}
 rows.append(row);(out/(top+'_result.json')).write_text(json.dumps(row,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
 print(top,row['result'],row['seconds'],text[-180:],flush=True)
 if not ok:sys.exit(1)
(root/'sim/compact_regression_rerun.json').write_text(json.dumps({'result':'PASS','tests':rows},ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
