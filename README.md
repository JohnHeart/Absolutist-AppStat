Absolutist Analytics: How to use AS3 library
================================

Initialization
--------------------------------
Just by starting up Absolutist Analytics, you will already generate several interesting analytics charts in the web interface.
    
    AppStat.init(stage, 'appID', '1.0.0', 'userUDID', AppStat.STORE_FACEBOOK);
    
Custom events
--------------------------------
With Events, you can collect more finegrained data about how players are using your game. Pass custom properties to get a nice visualization of the details.
	
    AppStat.logEvent('GameStarted');
    AppStat.logEvent('HintPressed', { count: 5 });
    
A / B Testing
--------------------------------
By setting splitter you can implement A / B Testing.
	
    AppStat.setSplitter('splitterName');

Purchase methods
--------------------------------
A person successfully completes a payment in your app
	
    AppStat.logPurchase('productID', 0.99, 25.0, 'UAH');
    