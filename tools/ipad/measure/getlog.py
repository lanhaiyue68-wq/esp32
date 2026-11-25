import asyncio, sys
sys.path.insert(0, r"E:\AgentStorage\esp32\iphone-agent-build13\tools\ipad")
import lan_usb_ipad as L
async def main():
    a = L.afc()
    if asyncio.iscoroutine(a): a = await a
    data = a.get_file_contents("/Documents/debug.log")
    if asyncio.iscoroutine(data): data = await data
    open(sys.argv[1], "wb").write(data)
    print(len(data))
asyncio.run(main())
