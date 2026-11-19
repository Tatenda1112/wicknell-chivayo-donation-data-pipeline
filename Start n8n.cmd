@echo off
rem Starts n8n with the "Execute Command" node switched on.
rem n8n 2.x hides that node by default; the workflow needs it to load the warehouse.
set NODES_EXCLUDE=[]
npx n8n
