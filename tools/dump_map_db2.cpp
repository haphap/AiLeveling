// SPDX-License-Identifier: GPL-2.0-or-later
// Standalone read-only adapter for the already built TrinityCore DB2 reader.
#include "DB2FileLoader.h"
#include "DB2FileSystemSource.h"
#include "ExtractorDB2LoadInfo.h"
#include <iostream>
#include <map>
#include <sstream>
int main(int argc, char** argv) {
    if (argc != 2) return 2;
    try {
        DB2FileSystemSource source(argv[1]);
        DB2FileLoader db; db.Load(&source, &MapLoadInfo::Instance);
        std::map<unsigned, std::string> rows;
        for (unsigned i=0; i<db.GetRecordCount(); ++i) {
            auto r=db.GetRecord(i); if (!r) continue;
            std::ostringstream out;
            out << int(r.GetUInt8("InstanceType")) << '\t' << int(r.GetUInt8("ExpansionID")) << '\t'
                << r.GetUInt16("AreaTableID") << '\t' << int(r.GetUInt8("MaxPlayers")) << '\t'
                << r.GetUInt32("WdtFileDataID") << '\t' << r.GetString("MapName") << '\t' << r.GetString("Directory");
            if (!rows.emplace(r.GetId(),out.str()).second) return 3;
        }
        auto decoded=rows.size();
        for (unsigned i=0; i<db.GetRecordCopyCount(); ++i) {
            auto c=db.GetRecordCopy(i);
            if (!rows.count(c.SourceRowId)) { std::cerr << "Missing copy source " << c.SourceRowId << '\n'; return 4; }
            if (!rows.emplace(c.NewRowId,rows.at(c.SourceRowId)).second) return 5;
        }
        std::cerr << "headerRecords=" << db.GetHeader().RecordCount << " recordSlots=" << db.GetRecordCount()
                  << " decodedRecords=" << decoded << " copyRecords=" << db.GetRecordCopyCount()
                  << " outputRecords=" << rows.size() << '\n';
        std::cout << "ID\tInstanceType\tExpansionID\tAreaTableID\tMaxPlayers\tWdtFileDataID\tMapName\tDirectory\n";
        for (auto const& [id,row]:rows) std::cout << id << '\t' << row << '\n';
    } catch (std::exception const& e) { std::cerr << e.what() << '\n'; return 1; }
}
