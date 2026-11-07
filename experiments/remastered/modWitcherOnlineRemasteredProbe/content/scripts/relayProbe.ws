import function WO_Send(payload : string) : bool;
import function WO_Poll() : int;
import function WO_Str(index : int) : string;

exec function wo_remastered_probe()
{
    var position : Vector;
    var area : name;
    var payload : string;

    if (!thePlayer)
    {
        return;
    }

    position = thePlayer.GetWorldPosition();
    area = theGame.GetCommonMapManager().GetCurrentArea();

    // MOVE expects x, y, z, w, heading, speed, and area in that order.
    payload = "move ";
    payload += position.X;
    payload += " ";
    payload += position.Y;
    payload += " ";
    payload += position.Z;
    payload += " ";
    payload += position.W;
    payload += " ";
    payload += thePlayer.GetHeading();
    payload += " 0 ";
    payload += area;

    if (WO_Send(payload))
    {
        thePlayer.DisplayHudMessage("Probe queued. Run wo_remastered_status() to check the relay.");
    }
    else
    {
        thePlayer.DisplayHudMessage("Probe could not send. Check WitcherOnline.log.");
    }
}

exec function wo_remastered_status()
{
    var i : int;
    var opcode : int;
    var localUsername : string;
    var playerId : int;
    var area : string;

    if (!thePlayer)
    {
        return;
    }

    localUsername = WO_Str(-4);
    for (i = 0; i < 32; i += 1)
    {
        opcode = WO_Poll();
        if (opcode < 0)
        {
            break;
        }

        // The relay echoes MOVE to its sender with a server-assigned player ID.
        if (opcode == 1 && WO_Str(-1) == localUsername && WO_Str(-3) == "8")
        {
            playerId = StringToInt(WO_Str(-2));
            area = WO_Str(7);
            if (playerId > 0 && area != "")
            {
                WO_Send("offline");
                thePlayer.DisplayHudMessage("Relay replied. Player " + playerId + ", area " + area);
                return;
            }
        }
    }

    WO_Send("offline");
    thePlayer.DisplayHudMessage("No relay reply. Check the Java server and WitcherOnline.log.");
}
