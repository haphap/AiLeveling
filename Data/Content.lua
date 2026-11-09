local _, A = ...
-- Runtime task facts come from QuestieDB and TaskFacts; optional service and dungeon data share this container.
A.Content = { schema = 1, interface = 16001, version = "unverified",
    quests = {}, nodes = {}, edges = {}, transit = {}, dungeons = {}, sources = {},
    services = {}, items = {}, gearSources = {}, progression = {verified=false,xpToLevel={}} }
