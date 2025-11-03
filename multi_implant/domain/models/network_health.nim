#[
    Domain Model: NetworkHealth
    Represents network health metrics for adaptive communication
]#

import times, math

type
    NetworkHealth* = object
        rtt*: float                  # Round-trip time in milliseconds
        consecutiveErrors*: int       # Consecutive network errors
        lastSuccessTime*: int64       # Timestamp of last successful communication
        isSlowNetwork*: bool         # Whether network is considered slow
        adaptiveMultiplier*: float  # Adaptive multiplier for polling intervals

proc newNetworkHealth*(): NetworkHealth =
    ## Create a new NetworkHealth instance with default values
    result = NetworkHealth(
        rtt: 50.0,                    # Start with 50ms baseline
        consecutiveErrors: 0,
        lastSuccessTime: epochTime().int64,
        isSlowNetwork: false,
        adaptiveMultiplier: 1.0
    )

proc updateOnSuccess*(health: var NetworkHealth, rtt: float) =
    ## Update network health metrics on successful communication
    # Ensure RTT is reasonable (between 1ms and 60s)
    let validRtt = max(min(rtt, 60000.0), 1.0)
    
    # Exponential moving average for RTT
    health.rtt = (health.rtt * 0.7) + (validRtt * 0.3)
    health.consecutiveErrors = 0
    health.lastSuccessTime = epochTime().int64
    
    # Determine if network is slow (RTT > 200ms)
    health.isSlowNetwork = health.rtt > 200.0
    
    # Calculate adaptive multiplier based on network conditions
    if health.rtt > 500.0:
        health.adaptiveMultiplier = 4.0  # Very slow network
    elif health.rtt > 200.0:
        health.adaptiveMultiplier = 2.0  # Slow network
    elif health.rtt > 100.0:
        health.adaptiveMultiplier = 1.5  # Medium network
    else:
        # Gradual reduction instead of immediate reset
        if health.adaptiveMultiplier > 1.0:
            health.adaptiveMultiplier = max(1.0, health.adaptiveMultiplier * 0.8)  # 20% reduction per success
        else:
            health.adaptiveMultiplier = 1.0  # Fast network

proc updateOnError*(health: var NetworkHealth) =
    ## Update network health metrics on communication error
    health.consecutiveErrors += 1
    let errorMultiplier = min(pow(2.0, float(health.consecutiveErrors)), 8.0)  # Max 8x backoff
    
    # Calculate RTT-based multiplier
    let rttBasedMultiplier = if health.rtt > 500.0: 4.0
                            elif health.rtt > 200.0: 2.0
                            elif health.rtt > 100.0: 1.5
                            else: 1.0
    
    # Use the higher of error-based or RTT-based multiplier
    health.adaptiveMultiplier = max(rttBasedMultiplier, errorMultiplier)

proc resetIfStuck*(health: var NetworkHealth) =
    ## Reset network health if stuck in bad state
    let currentTime = epochTime().int64
    let timeSinceLastUpdate = currentTime - health.lastSuccessTime
    
    # If no success for 5 minutes and multiplier is high, force reset
    if timeSinceLastUpdate > 300 and health.adaptiveMultiplier > 2.0:
        # Gradual reset instead of immediate
        health.adaptiveMultiplier = max(1.5, health.adaptiveMultiplier * 0.5)  # Half the multiplier
        health.consecutiveErrors = max(0, health.consecutiveErrors - 2)  # Reduce errors by 2
        health.rtt = min(health.rtt, 100.0)  # Cap RTT at reasonable value

proc getAdaptivePollingInterval*(health: var NetworkHealth, baseInterval: int): int =
    ## Calculate adaptive polling interval based on network health
    health.resetIfStuck()
    let adaptiveInterval = int(float(baseInterval) * health.adaptiveMultiplier)
    # Apply safety bounds: min 500ms, max 20s
    result = min(max(adaptiveInterval, 500), 20000)

proc getAdaptiveTimeout*(health: NetworkHealth, baseTimeout: int): int =
    ## Calculate adaptive timeout based on network health
    let adaptiveTimeout = int(float(baseTimeout) * health.adaptiveMultiplier)
    # Apply safety bounds: min 50ms, max 3s
    result = min(max(adaptiveTimeout, 50), 3000)

