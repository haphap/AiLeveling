#!/usr/bin/env python3
"""Read the pinned LibQuestDB public API; generate reference rewards/XP/objective facts."""
import hashlib
import argparse
import json
import math
import subprocess
import zipfile
from pathlib import Path
from import_cache_xp import load as load_cache_xp

ROOT = Path(__file__).resolve().parents[1]
SHA = '5da5f5b968521d60fc1f17ca6884118e2c41053a4d2aeb96440416662044e30b'


def lua(value):
    if value is None:
        return 'nil'
    if isinstance(value, bool):
        return 'true' if value else 'false'
    if isinstance(value, (int, float)):
        assert math.isfinite(value)
        return str(value)
    if isinstance(value, str):
        return json.dumps(value, ensure_ascii=False)
    if isinstance(value, list):
        return '{' + ','.join(lua(v) for v in value) + '}'
    return '{' + ','.join('[' + (k if k.isdigit() else lua(k)) + ']=' + lua(v) for k, v in sorted(value.items())) + '}'


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    archive = ROOT / '.dependencies/QuestDB-QuestDB-v0.1.0.zip'
    assert hashlib.sha256(archive.read_bytes()).hexdigest() == SHA
    package = ROOT / '.dependencies/QuestDB-0.1.0/QuestDB'
    names=['libs/LibStub/LibStub.lua','LibQuestDB-1.0.lua', *['Data/Forever/_core/' + n + '.lua' for n in ['Quests','Rewards','QuestXP','Drops']]]
    with zipfile.ZipFile(archive) as z:
        for name in names:
            assert (package/name).read_bytes()==z.read('QuestDB/'+name), 'Extracted source differs from pinned archive: '+name
    code = r'''
local base=assert(arg[1])
GetLocale=function() return 'enUS' end
dofile(base..'/libs/LibStub/LibStub.lua')
dofile(base..'/LibQuestDB-1.0.lua')
for _,name in ipairs({'Quests','Rewards','QuestXP','Drops'}) do dofile(base..'/Data/Forever/_core/'..name..'.lua') end
local lib=LibStub('LibQuestDB-1.0')
assert(lib.MINOR==20 and lib:GetSource()=='Forever')
local result={quests={},drops={}}
local items={}
for _,id in ipairs(lib:GetQuestIds()) do
 local q=lib:GetShippedQuest(id)
 local row={level=q.questLevel,hidden=q.hidden,group=q.suggestedPlayers,objectives={}}
 for _,spec in ipairs({{'npcs','npc'},{'objects','object'},{'items','item'}}) do
  for _,o in ipairs(q.objectives[spec[1]] or {}) do
   row.objectives[#row.objectives+1]={kind=spec[2],id=o.id,count=o.count}
   if spec[2]=='item' then items[o.id]=true end
  end
 end
 row.complex=#q.objectives.spells>0 or #q.objectives.explore>0 or q.objectives.rep~=nil
 local rewards=lib:GetRewards(id)
 if rewards then
  row.rewards={items=rewards.items,choices=rewards.choices,money=rewards.money or 0,
      spell=rewards.spell,spellCast=rewards.spellCast,srcItem=rewards.srcItem}
  local xp,previous={},nil
  for level=1,59 do
   local value=lib:GetQuestXP(id,level)
   if value~=previous and value~=nil then xp[#xp+1]={level,value} end
   previous=value
  end
  if #xp>0 then row.xp=xp end
 end
 result.quests[tostring(id)]=row
end
for id in pairs(items) do result.drops[tostring(id)]=lib:GetItemDrops(id) end
local function json(v)
 if v==nil then return 'null' end
 if type(v)=='boolean' or type(v)=='number' then return tostring(v) end
 if type(v)=='string' then return '"'..v:gsub('[%z\1-\31\\"]',function(c) return string.format('\\u%04x',c:byte()) end)..'"' end
 local parts={}
 if #v>0 then for i,x in ipairs(v) do parts[i]=json(x) end;return '['..table.concat(parts,',')..']' end
 for k,x in pairs(v) do parts[#parts+1]=json(tostring(k))..':'..json(x) end
 return '{'..table.concat(parts,',')..'}'
end
io.write(json(result))
'''
    loader = ROOT / 'dist/import-task-facts-loader.lua'
    loader.write_text(code)
    data = json.loads(subprocess.check_output(['lua5.1', str(loader), str(package)], text=True))
    for row in data['quests'].values():
        # Empty API arrays arrive as JSON objects; restore the intended shape.
        for key in ['objectives']:
            if row.get(key) == {}:
                row[key] = []
        if row.get('rewards'):
            for key in ['items', 'choices']:
                if row['rewards'][key] == {}:
                    row['rewards'][key] = []
    data.update(source='LibQuestDB-0.1.0-Forever', clientVerified=False)
    data['cacheXP'], cache_report = load_cache_xp()
    generated = ('local _,A=...\n-- Generated LibQuestDB facts (MIT) and Efficient Games XP/objectives (CC BY 4.0).\n'
                 '-- Data from Efficient Games (https://efficient.games); changed to XP curves, basic objectives, progress-location references and quest-item uses. See docs/TASK_XP_AUDIT.json.\n'
                 'A.TaskFacts=' + lua(data) + '\n')
    effective = json.loads((ROOT / 'docs/EFFECTIVE_DATA_AUDIT.json').read_text())['base']['quests']
    report = {'source': data['source'], 'archiveSHA256': SHA,
              'url': 'https://www.curseforge.com/wow/addons/questdb/files/9014639',
              'clientVerified': False, 'scope': 'Classic server reference facts on Forever client XP tiers; QuestieDB qualifications remain authoritative.',
              'quests': len(data['quests']), 'matchedQuestieIds': len(set(data['quests']) & set(effective)),
              'rewardRows': sum('rewards' in r for r in data['quests'].values()),
              'xpRows': sum('xp' in r for r in data['quests'].values()),
              'objectives': sum(len(r['objectives']) for r in data['quests'].values()),
              'itemDropRows': len(data['drops']), 'sourceFiles': {}}
    report['missingQuestLevels']=sorted(int(id) for id,row in data['quests'].items() if 'level' not in row)
    for name in ['LibQuestDB-1.0.lua', *['Data/Forever/_core/' + n + '.lua' for n in ['Quests', 'Rewards', 'QuestXP', 'Drops']]]:
        report['sourceFiles'][name] = hashlib.sha256((package / name).read_bytes()).hexdigest()
    report['cacheXP'] = {'audit': 'TASK_XP_AUDIT.json', 'rows': len(data['cacheXP']['quests'])}
    outputs = {ROOT / 'Data/TaskFacts.lua': generated,
               ROOT / 'docs/TASK_FACTS_AUDIT.json': json.dumps(report, indent=2, ensure_ascii=False) + '\n',
               ROOT / 'docs/TASK_XP_AUDIT.json': json.dumps(cache_report, indent=2, ensure_ascii=False) + '\n'}
    for path, value in outputs.items():
        if args.check:
            assert path.read_text() == value, f'Generated facts differ: {path}'
        else:
            path.write_text(value)
    print(json.dumps({k: report[k] for k in ['quests', 'matchedQuestieIds', 'rewardRows', 'xpRows', 'objectives']}))


if __name__ == '__main__':
    main()
