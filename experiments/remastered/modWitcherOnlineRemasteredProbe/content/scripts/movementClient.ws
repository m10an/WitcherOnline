@addField(CR4Game)
var wo_remasteredClient : WO_RemasteredMovementClient;

@addMethod(CR4Game)
public function WO_GetRemasteredClient() : WO_RemasteredMovementClient
{
    if (!this.wo_remasteredClient)
    {
        this.wo_remasteredClient = new WO_RemasteredMovementClient in this;
    }
    return this.wo_remasteredClient;
}

class WO_RemasteredMovementClient
{
    private var running : bool;
    private var area : name;
    private var lastTick : float;
    private var lastReply : float;
    private var replicas : array<WO_RemasteredReplica>;
    private var actorTemplate : CEntityTemplate;
    private var idleTree : IAITree;

    public function IsRunning() : bool
    {
        return running;
    }

    public function Start()
    {
        if (!thePlayer)
        {
            return;
        }
        actorTemplate = (CEntityTemplate)LoadResource("characters\npc_entities\main_npc\geralt_npc.w2ent", true);
        idleTree = new CAIDoNothingAction in this;
        if (!actorTemplate || !idleTree)
        {
            thePlayer.DisplayHudMessage("Multiplayer could not load the base-game replica resources.");
            return;
        }
        ClearReplicas();
        running = true;
        lastReply = 0;
        Resume();
        thePlayer.DisplayHudMessage("Movement sharing started. Use wo_remastered_status() or wo_remastered_stop().");
    }

    public function Resume()
    {
        if (running && thePlayer)
        {
            area = theGame.GetCommonMapManager().GetCurrentArea();
            lastTick = theGame.GetEngineTimeAsSeconds();
            thePlayer.RemoveTimer('WO_RemasteredTick');
            thePlayer.AddTimer('WO_RemasteredTick', 0.05, true);
        }
    }

    public function Suspend()
    {
        if (thePlayer)
        {
            thePlayer.RemoveTimer('WO_RemasteredTick');
        }
        ClearReplicas();
        WO_Send("offline");
    }

    public function Stop()
    {
        running = false;
        Suspend();
    }

    private function ClearReplicas()
    {
        var i : int;
        for (i = 0; i < replicas.Size(); i += 1)
        {
            replicas[i].Despawn();
        }
        replicas.Clear();
    }

    public function Tick()
    {
        var i : int;
        var opcode : int;
        var now, delta : float;

        if (!running || !thePlayer)
        {
            return;
        }
        now = theGame.GetEngineTimeAsSeconds();
        delta = ClampF(now - lastTick, 0, 0.2);
        lastTick = now;
        if (area != theGame.GetCommonMapManager().GetCurrentArea())
        {
            ClearReplicas();
            area = theGame.GetCommonMapManager().GetCurrentArea();
        }

        for (i = 0; i < 128; i += 1)
        {
            opcode = WO_Poll();
            if (opcode < 0)
            {
                break;
            }
            if (opcode == 1)
            {
                ReceiveMovement(now);
            }
            else if (opcode >= 6 && opcode <= 9)
            {
                Stop();
                thePlayer.DisplayHudMessage("Server rejected the connection. Check username and server access.");
                return;
            }
        }
        WO_Send(WO_RemasteredMovementPayload());

        for (i = replicas.Size() - 1; i >= 0; i -= 1)
        {
            if (now - replicas[i].lastSeen > 5)
            {
                replicas[i].Despawn();
                replicas.Erase(i);
            }
            else
            {
                if (replicas[i].area == NameToString(area) && VecDistance(thePlayer.GetWorldPosition(), replicas[i].target) <= 150)
                {
                    replicas[i].Render(delta, actorTemplate, idleTree);
                }
                else
                {
                    replicas[i].Despawn();
                }
            }
        }
    }

    private function ReceiveMovement(now : float)
    {
        var i, playerId, sequence : int;
        var position : Vector;
        var heading, speed : float;
        var replica : WO_RemasteredReplica;

        if (WO_Str(-3) != "8")
        {
            return;
        }
        playerId = StringToInt(WO_Str(-2));
        sequence = StringToInt(WO_Str(0));
        if (playerId <= 0 || sequence <= 0 || sequence > 2000000000)
        {
            return;
        }
        if (WO_Str(-1) == WO_Str(-4))
        {
            lastReply = now;
            return;
        }
        for (i = 0; i < replicas.Size(); i += 1)
        {
            if (replicas[i].playerId == playerId)
            {
                replica = replicas[i];
                break;
            }
        }
        position.X = StringToFloat(WO_Str(1));
        position.Y = StringToFloat(WO_Str(2));
        position.Z = StringToFloat(WO_Str(3));
        position.W = 1;
        heading = StringToFloat(WO_Str(5));
        speed = StringToFloat(WO_Str(6));
        if (position.X != position.X || position.Y != position.Y || position.Z != position.Z || heading != heading || speed != speed)
        {
            return;
        }
        if (AbsF(position.X) > 100000 || AbsF(position.Y) > 100000 || AbsF(position.Z) > 100000 || AbsF(heading) > 100000 || AbsF(speed) > 100)
        {
            return;
        }
        if (!replica)
        {
            if (replicas.Size() >= 64)
            {
                return;
            }
            replica = new WO_RemasteredReplica in this;
            replica.playerId = playerId;
            replicas.PushBack(replica);
        }
        replica.Apply(sequence, position, heading, speed, WO_Str(7), now);
    }

    public function ShowStatus()
    {
        var i, visible : int;
        for (i = 0; i < replicas.Size(); i += 1)
        {
            if (replicas[i].actor)
            {
                visible += 1;
            }
        }
        if (lastReply > 0)
        {
            thePlayer.DisplayHudMessage("Movement sharing: replicas " + visible + ", relay reply " + (theGame.GetEngineTimeAsSeconds() - lastReply) + " seconds ago.");
        }
        else
        {
            thePlayer.DisplayHudMessage("Movement sharing: waiting for the relay.");
        }
    }
}

class WO_RemasteredReplica
{
    public var playerId : int;
    public var target : Vector;
    public var area : string;
    public var lastSeen : float;
    public var actor : CActor;
    private var lastSequence : int;
    private var heading, speed, nextSpawnAt : float;

    public function Apply(sequence : int, position : Vector, newHeading, newSpeed : float, newArea : string, now : float)
    {
        var distance : int;
        if (lastSequence > 0)
        {
            distance = sequence - lastSequence;
            if (distance < 0)
            {
                distance += 2000000000;
            }
            if (distance == 0 || distance >= 1000000000)
            {
                return;
            }
        }
        lastSequence = sequence;
        target = position;
        area = newArea;
        heading = newHeading;
        speed = ClampF(newSpeed, 0, 4);
        lastSeen = now;
    }

    public function Render(delta : float, actorTemplate : CEntityTemplate, idleTree : IAITree)
    {
        var position : Vector;
        var rotation : EulerAngles;
        var movement : CMovingAgentComponent;

        rotation.Yaw = heading;
        if (!actor)
        {
            if (theGame.GetEngineTimeAsSeconds() < nextSpawnAt)
            {
                return;
            }
            nextSpawnAt = theGame.GetEngineTimeAsSeconds() + 2;
            actor = (CActor)theGame.CreateEntity(actorTemplate, target, rotation, true, true, true, PM_DontPersist);
            if (!actor)
            {
                return;
            }
            actor.AddTag('WO_RemasteredReplica');
            actor.SetImmortalityMode(AIM_Invulnerable, AIC_Default, true);
            actor.EnableCollisions(false);
            actor.EnableCharacterCollisions(false);
            actor.EnablePhysicalMovement(false);
            actor.SetGameplayVisibility(false);
            actor.SetCanPlayHitAnim(false);
            actor.SetAttitude(thePlayer, AIA_Friendly);
            actor.ForceAIBehavior(idleTree, BTAP_AboveEmergency2);
        }
        position = actor.GetWorldPosition();
        if (VecDistance(position, target) > 8)
        {
            position = target;
        }
        else
        {
            position += (target - position) * ClampF(delta * 15, 0, 1);
        }
        actor.SetRawPlacement(position, rotation);
        movement = actor.GetMovingAgentComponent();
        if (movement)
        {
            movement.SetGameplayRelativeMoveSpeed(speed);
            movement.SetGameplayMoveDirection(heading);
        }
    }

    public function Despawn()
    {
        if (actor)
        {
            actor.Destroy();
            actor = NULL;
        }
    }
}

@addMethod(CR4Player)
timer function WO_RemasteredTick(delta : float, timerId : int)
{
    theGame.WO_GetRemasteredClient().Tick();
}

@wrapMethod(CR4Player)
function OnSpawned(spawnData : SEntitySpawnData)
{
    wrappedMethod(spawnData);
    theGame.WO_GetRemasteredClient().Resume();
}

@wrapMethod(CR4Game)
function OnBeforeWorldChange(worldName : string)
{
    if (this.wo_remasteredClient)
    {
        this.wo_remasteredClient.Suspend();
    }
    wrappedMethod(worldName);
}

@wrapMethod(CR4Game)
function OnGameEnded()
{
    if (this.wo_remasteredClient)
    {
        this.wo_remasteredClient.Stop();
    }
    wrappedMethod();
}

exec function wo_remastered_start()
{
    theGame.WO_GetRemasteredClient().Start();
}

exec function wo_remastered_stop()
{
    theGame.WO_GetRemasteredClient().Stop();
    if (thePlayer)
    {
        thePlayer.DisplayHudMessage("Movement sharing stopped.");
    }
}
