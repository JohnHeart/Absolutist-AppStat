package com.absolutist
{
	
	import com.hurland.crypto.hash.MD5;
	
	import flash.display.Stage;
	import flash.events.ErrorEvent;
	import flash.events.Event;
	import flash.events.IOErrorEvent;
	import flash.events.SecurityErrorEvent;
	import flash.net.SharedObject;
	import flash.net.URLLoader;
	import flash.net.URLRequest;
	import flash.net.URLRequestMethod;
	import flash.system.Capabilities;
	import flash.utils.ByteArray;
	import flash.utils.Endian;
	import flash.utils.getTimer;
	
	/**
	 * Absolutist Analytics.
	 * @author pkulikov
	 * 
	 */	
	public class AppStat
	{
		public static const STORE_IOS:String 								= "ios";
		public static const STORE_AMAZON:String 						= "amazon";
		public static const STORE_ANDROID:String 						= "android";
		public static const STORE_WILDTANGENT:String 				= "wildtangent";
		public static const STORE_WP8:String 								= "wp8";
		public static const STORE_BLACKBERRY:String 				= "blackberry";
		public static const STORE_FORTUMO:String 						= "fortumo";
		public static const STORE_SAMSUNG:String 						= "samsung";
		public static const STORE_FACEBOOK:String 					= "webfb";
		public static const STORE_VKONTAKTE:String 					= "webvk";
		public static const STORE_ODNOKLASSNIKI:String 			= "webok";
		public static const STORE_YAHOO:String 							= "webya";
		
		private static const PROTOCOL_VERSION:int 					= 12; // increment 2
		private static const PACKAGE_LIMIT:int 							= 1024;
		private static const FLUSH_PACKAGE_LENGTH:int 			= 4;
		private static const AUTO_FLUSH:int 								= 3*60; // seconds
		
		private static const PACKAGE_INSTALL_UPDATE:Array 	= [0, 0];
		private static const PACKAGE_START_SESSION:Array 		= [1, 0];
		private static const PACKAGE_END_SESSION:Array 			= [2, 0];
		private static const PACKAGE_SPLITTER:Array 				= [3, 0];
		private static const PACKAGE_EVENT:Array 						= [4, 0];
		private static const PACKAGE_PURCHASE:Array 				= [5, 0];
		
		private static const EVENT_INSTALL:String 					= "install";
		private static const EVENT_UPDATE:String 						= "update";
		private static const EVENT_START_SESSION:String 		= "startSession";
		private static const EVENT_CLOSE_SESSION:String 		= "closeSession";
		
		/** @private App ID */
		private static var mAppID:String;
		
		/** @private App version */
		private static var mAppVersion:int;
		
		/** @private Unique device ID */
		private static var mUniqueDeviceId:String;
		
		/** @private Unique device ID buffer */
		private static var mUniqueDeviceIdBuf:ByteArray;
		
		/** @private Store */		
		private static var mStore:String;
		
		/** @private Referer */		
		private static var mReferer:String;
		
		/** @private Device OS */		
		private static var mDeviceOS:String;
		
		/** @private Device OS version */		
		private static var mDeviceOSVersion:String;
		
		/** @private Device model */		
		private static var mDeviceModel:String;
		
		/** @private Server URL */
		private static var mServerURL:String;
		
		/** @private Developer mode */
		private static var mDeveloperMode:Boolean;
		
		/** @private Event cache */
		private static var mCache:Object;
		
		/** @private Session state */
		private static var mSessionEnabled:Boolean;
		
		/** @private Session time */
		private static var mSessionTime:Number;
		
		/** @private AppStat is blocked */
		private static var mBlocked:Boolean;
		
		/** @private Helpers */
		private static var mTimestamp:uint;
		private static var mAutoFlushTimer:Number;
		private static var mURLLoader:URLLoader;
		private static var mIsInstall:Boolean;
		private static var mIsUpdate:Boolean;
		private static var mIsFirstSession:Boolean;
		private static var mMD5:MD5;
		
		/**
		 * Initialization of Absolutist Analytics.
		 * @param appId Application id.
		 * @param appVersion Application version (eg "1.0.0").
		 * @param uniqueDeviceId Unique device ID.
		 * @param store Store name (eg AppStat.STORE_FACEBOOK).
		 * @param serverURL Optional.
		 * @param developerMode Optional.
		 * 
		 */				
		public static function init(stage:Stage, appId:String, appVersion:String, uniqueDeviceId:String, store:String, referer:String = null, serverURL:String = null, developerMode:Boolean = false):void
		{
			const DEFAULT_VERSION:String = '1.0.0';
			const DEFAULT_STORE:String = 'web';
			const DEFAULT_OS:String = 'Flash';
			const DEFAULT_SERVER:String = 'http://data.absolutist.com/ev/dt.php';
			
			mAppID = appId || '';
			mAppVersion = FORMAT_APP_VERSION(appVersion || DEFAULT_VERSION);
			mUniqueDeviceId = uniqueDeviceId || '';
			mUniqueDeviceIdBuf = NEW_BYTE_ARRAY();
			mUniqueDeviceIdBuf.writeUTFBytes(mUniqueDeviceId);
			mDeviceOS = DEFAULT_OS;
			mDeviceOSVersion = Capabilities.os;
			mDeviceModel = GET_FLASH_PLAYER();
			mStore = store || DEFAULT_STORE;
			mReferer = referer || '';
			mServerURL = serverURL || DEFAULT_SERVER;
			mDeveloperMode = developerMode;
			
			if (!stage)
			{
				log("Error -> the stage is not defined");
				mBlocked = true;
				return;
			}
			
			if (!mAppID.length)
			{
				log("Error -> invalid appId");
				mBlocked = true;
				return;
			}
			
			if (!mUniqueDeviceId.length)
			{
				log("Error -> invalid uniqueDeviceId");
				mBlocked = true;
				return;
			}
			
			mMD5 = new MD5;
			mURLLoader = new URLLoader;
			mURLLoader.addEventListener(Event.COMPLETE, handlerComplete);
			mURLLoader.addEventListener(IOErrorEvent.IO_ERROR, handlerError);
			mURLLoader.addEventListener(SecurityErrorEvent.SECURITY_ERROR, handlerError);
			
			mIsFirstSession = true; 																		// for EVENT_START_SESSION
			loadCache();																								// load cache
			resumeSession();																						// resume session
			mSessionTime = 0;																						// session time
			
			stage.addEventListener(Event.DEACTIVATE, pauseSession);			// pause
			stage.addEventListener(Event.ACTIVATE, resumeSession);			// resume
			stage.addEventListener(Event.ENTER_FRAME, advanceTime);			// timer
		}
		
		
		//===============================================================================================
		//
		//																					Protocol
		//
		//===============================================================================================
		
		
		/**
		 * Custom event. The parameter values can be only integers.
		 * @param eventName Name of the event.
		 * @param parameters Parameters for event (eg { param1: 100, param2: 200 }).
		 * 
		 */		
		public static function logEvent (name:String, parameters:Object = null):void
		{
			if (mBlocked) return;
			if (!mCache.idSession) return;
			
			parameters = parameters || {};
			
			// дополнительно к каждому событию добавляем два параметра
			parameters.t_log_cal = Math.round(24 * Math.log(int((GET_DATE_UTC() - mCache.installDate)/1000)));	// 24*lnвремя в секундах с момента инсталяции (24*ln)
			parameters.t_log_play = Math.round(24 * Math.log(int(mCache.playTime)));														// игровое время в секундах с момента инсталяции (24*ln)
			
			var len:int = 0;
			var params:ByteArray = NEW_BYTE_ARRAY();
			for (var param:String in parameters)
			{
				var value:Number = parameters[param];
				if (isNaN(value)) value = -1; 				// -1 by default
				writeUTFBytes(params, param);					// строка - имя параметра
				writeDouble(params, value);						// 8 байт - значение
				len++;
			}
			
			var pack:ByteArray = NEW_BYTE_ARRAY();
			writeUTFBytes(pack, name);							// строка - имя события
			writeDouble(pack, GET_DATE_UTC());			// 8 байт - дата события в UTC
			writeDouble(pack, GET_DATE_LOCAL());		// 8 байт - локальная дата события
			writeInt(pack, int(mSessionTime));			// 4 байт - время работы приложения в секундах
			writeInt(pack, len);										// 4 байт - число параметров
			pack.writeBytes(params);								// далее идут последовательно пары параметр-значение
			
			
			pushPack(addUniform(PACKAGE_EVENT, pack));
		}
		
		/**
		 * Add the statistics of purchase.
		 * @param productID Product ID (eg "com.companyname.purchasename").
		 * @param priceUSD Price USD (eg 0.99).
		 * @param price Price in real currency (eg 25.0).
		 * @param currency Real currency (eg "UAH").
		 * 
		 */		
		public static function logPurchase (productID:String, priceUSD:Number, price:Number, currency:String):void
		{
			if (mBlocked) return;
			
			var pack:ByteArray = NEW_BYTE_ARRAY();
			writeInt(pack, mCache.purchaseNum);				// 4 байта - порядковый номер этой покупки у игрока; (int)
			mCache.purchaseNum++;
			writeFloat(pack, price);									// 4 байта - цена покупки в реальной(оригинальной) валюте; (float) 
			writeFloat(pack, priceUSD);								// 4 байта - цена покупки в условной валюте; (float)
			mCache.purchasesSum += priceUSD;
			writeFloat(pack, mCache.purchasesSum);		// 4 байта - сумма покупок, совершенных игроком за реальные деньги, включая эту покупку; (float)
			writeUTFBytes(pack, mDeviceOS);						// строка - платформа; 
			writeUTFBytes(pack, currency);						// строка - код валюты; 
			writeUTFBytes(pack, productID);						// строка - ID покупки(внутренний); 
			writeUTFBytes(pack, productID);						// строка - ID покупки(внешний); 
			writeUTFBytes(pack, '');									// строка - ID транзакции. 
			
			pushPack(addUniform(PACKAGE_PURCHASE, pack));
			
			saveCache();
		}
		
		/**
		 * Branching statistics.
		 * @param name The splitter name.
		 * 
		 */		
		public static function setSplitter(name:String):void
		{
			if (mBlocked) return;
			
			var pack:ByteArray = NEW_BYTE_ARRAY();
			writeUTFBytes(pack, name);							// строка - имя сплиттера
			
			pushPack(addUniform(PACKAGE_SPLITTER, pack));
		}
		
		/**
		 * @private Pause session.
		 * Call this method when the Event.DEACTIVATE was thrown.
		 */			
		private static function pauseSession(event:Event = null):void
		{
			if (mBlocked) return;
			if (!mCache.sessionStart || !mCache.idSession) return;
			
			mSessionEnabled = false;
			
			var pack:ByteArray = NEW_BYTE_ARRAY();
			writeDouble(pack, GET_DATE_UTC());																		// 8 байт - дата закрытия сессии в UTC
			writeDouble(pack, GET_DATE_LOCAL());																	// 8 байт - локальная дата закрытия сессии
			writeInt(pack, int((GET_DATE_UTC() - mCache.sessionStart) / 1000));		// 4 байт - время сессии в секундах
			
			logEvent(EVENT_CLOSE_SESSION);
			pushPack(addUniform(PACKAGE_END_SESSION, pack));
			
			delete mCache.sessionStart;
			delete mCache.idSession;
			
			saveCache();
		}
		
		/**
		 * @private Resume session.
		 * Call this method when the Event.ACTIVATE was thrown.
		 */
		private static function resumeSession(event:Event = null):void
		{
			if (mBlocked) return;
			
			mSessionEnabled = true;
			mCache.sessionStart = GET_DATE_UTC();
			mCache.idSession = GENERATE_ID();
			
			var pack:ByteArray = NEW_BYTE_ARRAY();
			writeDouble(pack, GET_DATE_UTC());					// 8 байт - дата старта сессии в UTC
			writeDouble(pack, GET_DATE_LOCAL());				// 8 байт - локальная дата старта сессии
			
			pushPack(addUniform(PACKAGE_START_SESSION, pack));
			
			if (mIsInstall || mIsUpdate) {
				logEvent(mIsInstall ? EVENT_INSTALL : EVENT_UPDATE, { version: mAppVersion });
				mIsInstall = mIsUpdate = false;
			}
			
			logEvent(EVENT_START_SESSION, { first: mIsFirstSession ? 1:0 });
			mIsFirstSession = false;
			mAutoFlushTimer = AUTO_FLUSH;	// countdown
		}
		
		/**
		 * @private Advance the time. 
		 * @param event Event.ENTER_FRAME
		 * 
		 */		
		private static function advanceTime (event:Event):void
		{
			if (!mSessionEnabled)
			{
				mTimestamp = getTimer();
				return;
			}
			
			var time:Number = (getTimer() - mTimestamp) / 1000;
			mTimestamp = getTimer();
			
			mSessionTime += time;
			mCache.playTime += time;
			mAutoFlushTimer -= time;
			
			if (mAutoFlushTimer <= 0)
			{
				log("Timeout");
				flush();
				mAutoFlushTimer = AUTO_FLUSH;
			}
		}
		
		/**
		 * @private Add package to send. 
		 * @param pack Package data.
		 * 
		 */		
		private static function pushPack (pack:ByteArray):void
		{
			var lastIndex:int = mCache.waitingPacks.length - 1;	// from the end
			if (lastIndex < 0)
			{
				mCache.waitingPacks.push([]);	// add a new array of packages
				lastIndex = 0;
			}
			
			var currentPack:Array = mCache.waitingPacks[lastIndex];	// current list of packages
			var currentPackLen:uint = 0;	// the sum of the lengths of all packages
			for each (var p:ByteArray in currentPack) currentPackLen += p.length;
			
			// check package size limit
			if (currentPackLen + pack.length >= PACKAGE_LIMIT)
			{
				// check count of packages
				if (mCache.waitingPacks.length + 1 > FLUSH_PACKAGE_LENGTH)
				{
					log("Package limit");
					flush(); // send packages
				}
				
				mCache.waitingPacks.push([]);	// add next array of packages
				currentPack = mCache.waitingPacks[mCache.waitingPacks.length - 1];
			}
			
			currentPack[currentPack.length] = pack;	// push
		}
		
		/**
		 * @private Add uniform for package.
		 * @param type Package type.
		 * @param pack Package data.
		 * @return 
		 * 
		 */
		private static function addUniform (type:Array, pack:ByteArray):ByteArray
		{
			var result:ByteArray = NEW_BYTE_ARRAY();
			
			writeByte(result, type[0]);									// 1 байта - тип пакета
			writeShort(result, type[1]);								// 2 байта - формат пакета
			switch (type)
			{
				case PACKAGE_INSTALL_UPDATE:
					result.writeBytes(mCache.idUpdate);			// 8 байт - локальный id инсталяции/обновления
					result.writeBytes(mCache.idInstall);		// 8 байт - локальный id инсталяции
					break;
				
				case PACKAGE_START_SESSION:
				case PACKAGE_END_SESSION:
				case PACKAGE_EVENT:
					result.writeBytes(mCache.idUpdate);			// 8 байт - локальный id инсталяции/обновления
					result.writeBytes(mCache.idSession);		// 8 байт - локальный id сессии
					break;
				
				case PACKAGE_SPLITTER:
					result.writeBytes(mCache.idInstall);		// 8 байт - локальный id инсталяции
					break;
				
				case PACKAGE_PURCHASE:
					writeDouble(result, GET_DATE_UTC());		// 8 байт - дата покупки в UTC
					writeDouble(result, GET_DATE_LOCAL());	// 8 байт - локальная дата покупки
					result.writeBytes(mCache.idInstall);		// 8 байт - локальный id инсталяции
					break;
			}
			writeInt(result, mCache.idPack);						// 4 байта - локальный id пакета
			result.writeBytes(pack);
			
			mCache.idPack++;
			return result;
		}
		
		/**
		 * @private Add a header for a number of packages.
		 * @param list Packages.
		 * @return Header data.
		 * 
		 */		
		private static function addHeader (list:Array):ByteArray
		{
			var packs:ByteArray = NEW_BYTE_ARRAY();
			for each (var ba:ByteArray in list) packs.writeBytes(ba);
			
			var result:ByteArray = NEW_BYTE_ARRAY();
			
			var h:ByteArray = NEW_BYTE_ARRAY();
			writeShort(h, PROTOCOL_VERSION);																// 2 байта - формат основного пакета
			writeUTFBytes(h, mAppID);																				// строка - ID приложения
			writeInt(h, mAppVersion);																				// 4 байта - версия приложения
			writeUTFBytes(h, mUniqueDeviceId);															// строка - уникальный ID устройства
			writeShort(h, list.length);																			// 2 байта - количество пакетов
			
			var sum:uint = 0;
			h.position = packs.position = 0;
			while (h.bytesAvailable) sum += h.readUnsignedByte();						// 4 байта - контрольная сумма всех последующих байт основного пакета
			while (packs.bytesAvailable) sum += packs.readUnsignedByte();
			
			writeInt(result, sum);
			result.writeBytes(h);
			result.writeBytes(packs);																				// далее идут последовательно пакеты различных типов
			
			return result;
		}
		
		/**
		 * @private Create cache.
		 */		
		private static function createCache ():void
		{
			mCache = {};
			mCache.idInstall = GENERATE_INSTALL_ID();	// the first 8 bytes of the device ID hash
			mCache.idUpdate = mCache.idInstall;				// random 8 bytes
			mCache.installDate = GET_DATE_UTC();			// install time
			mCache.idPack = 0;												// continuous numbering packets
			mCache.playTime = 0;											// play time
			mCache.appVersion = mAppVersion;					// app version
			mCache.purchaseNum = 0;										// number of purchases
			mCache.purchasesSum = 0;									// sum of of purchases
			mCache.waitingPacks = [];									// packages waiting to be sent
			mCache.sendingPacks = [];									// packages for sending
		}
		
		/**
		 * @private Load cache from SharedObject.
		 */		
		private static function loadCache():void
		{
			var so:SharedObject;
			var data:Object;
			
			try
			{
				so = SharedObject.getLocal('appstat');
				if (so)
				{
					data = so.data.cache || null;
					so.close();
				}
			} catch (e:Error) { log(e.message); }
			
			if (!data)
			{
				createCache();
				mIsInstall = true;
			} else
			{
				try
				{
					mCache = data;
				} catch (error:Error)
				{
					createCache();
				}
				
				if (mCache.appVersion != mAppVersion)
				{
					mCache.appVersion = mAppVersion
					mCache.idUpdate = GENERATE_ID();
					
					mIsUpdate = true;
				}
				
				if (!mCache.waitingPacks) mCache.waitingPacks = [];
				if (!mCache.sendingPacks) mCache.sendingPacks = [];
				
				if (mCache.sendingPacks.length > 0)
				{
					log("Found incomplete packages");
					send();
				}
			}
			
			if (mIsInstall || mIsUpdate)
			{
				var pack:ByteArray = NEW_BYTE_ARRAY();
				writeByte(pack, mIsInstall ? 0 : 1);
				writeDouble(pack, GET_DATE_UTC());
				writeDouble(pack, GET_DATE_LOCAL());
				writeByte(pack, 0); 																							// jailbrake
				writeInt(pack, mCache.appVersion);																// app version
				writeUTFBytes(pack, mDeviceOS);																		// device os
				writeUTFBytes(pack, mDeviceOSVersion);														// device os version
				writeUTFBytes(pack, mDeviceModel);																// device model
				writeUTFBytes(pack, Capabilities.language.replace('-', '_'));			// locale
				writeUTFBytes(pack, mStore);																			// store
				writeUTFBytes(pack, mReferer);																		// referer
				
				pushPack(addUniform(PACKAGE_INSTALL_UPDATE, pack));
			}
		}
		
		/**
		 * @private Save cache to SharedObject.
		 */		
		private static function saveCache():void
		{
			var so:SharedObject;
			
			try
			{
				so = SharedObject.getLocal('appstat');
				so.data.cache = mCache;
				so.flush();
				so.close();
			} catch (e:Error) { log(e.message); }
		}
		
		/**
		 * @private Send accumulated packages.
		 */		
		private static function flush():void
		{
			log("Flush");
			
			mCache.sendingPacks = mCache.sendingPacks.concat(mCache.waitingPacks);
			mCache.waitingPacks.length = 0;
			send();
		}
		
		/**
		 * @private To send all packages.
		 */		
		private static function send ():void
		{
			const CONTENT_TYPE:String = 'application/octet-stream';
			
			if (mCache.sendingPacks.length > 0)
			{
				var data:ByteArray = addHeader(mCache.sendingPacks[0]);
				
				// verifying (developer mode only)
				if (mDeveloperMode)
				{
					if (!verify(data))
					{
						mCache.sendingPacks.shift();
						log("Error in package");
						send();
						return;
					}
				}
				
				var req:URLRequest = new URLRequest(mServerURL);
				req.method = URLRequestMethod.POST;
				req.contentType = CONTENT_TYPE;
				req.data = data;
				
				try
				{
					mURLLoader.load(req);
				} catch (error:Error)
				{
					mCache.sendingPacks.shift();
					log(error);
					send();
				}
			}
		}
		
		/** @private Write 1 byte. */
		private static function writeByte (target:ByteArray, value:int):void
		{
			target.writeByte(value);
		}
		
		/** @private Write 2 bytes. */
		private static function writeShort (target:ByteArray, value:int):void
		{
			target.writeShort(value);
		}
		
		/** @private Write 4 bytes. */
		private static function writeInt (target:ByteArray, value:int):void
		{
			target.writeUnsignedInt(uint(value));
		}
		
		/** @private Write 4 bytes. */
		private static function writeFloat (target:ByteArray, value:Number):void
		{
			target.writeFloat(value);
		}
		
		/** @private Write 8 bytes. */
		private static function writeDouble (target:ByteArray, value:Number):void
		{
			// only whole numbers
			value = Math.floor(value);
			
			if (value >= 0)
			{
				// split into 2 uint
				var u1:uint = value % Math.pow(256, 4);
				var u2:uint = value / Math.pow(256, 4);
				
				// write
				target.writeUnsignedInt(u1);
				target.writeUnsignedInt(u2);
			} else
			{
				target.writeInt(value);
				target.writeByte(0xFF);
				target.writeByte(0xFF);
				target.writeByte(0xFF);
				target.writeByte(0xFF);
			}
		}
		
		/** @private Write UTF8 string */
		private static function writeUTFBytes (target:ByteArray, value:String):void
		{
			target.writeUTFBytes(value);
			target.writeByte(0);
		}
		
		
		//===============================================================================================
		//
		//																		Server responses
		//
		//===============================================================================================
		
		
		private static function handlerComplete(event:Event):void
		{
			var response:String = mURLLoader.data || '';
			var success:Boolean = response.toLowerCase() == "ok";
			if (success)
			{
				log("Sending completed successfully");
				mCache.sendingPacks.shift();
				send();
			} else
			{
				log("Sending error: " + response);
			}
			
			saveCache();
		}
		
		private static function handlerError(event:ErrorEvent):void
		{
			log("Sending error: " + event.text);
		}
		
		
		//===============================================================================================
		//
		//																					Helpers
		//
		//===============================================================================================
		
		
		private static function FORMAT_APP_VERSION (value:String):int
		{
			var split:Array = value.split(".");
			for (var i:int = 0; i < 3; ++i)
				split[i] = split[i] != undefined ? parseInt(split[i]) : 0;
			return split[0]*1000000 + split[1]*1000 + split[2]*1;
		}
		
		private static function GET_FLASH_PLAYER():String
		{
			const TAG:String = 'FP ';
			var fp:String = Capabilities.version.split(',').join('.');
			var index:int = fp.indexOf(' ');
			if (index != -1) return TAG + fp.substring(index + 1, fp.length);
			else return TAG + fp;
		}
		
		private static function GET_DATE_UTC ():Number
		{
			return new Date().time;
		}
		
		private static function GET_DATE_LOCAL ():Number
		{
			var date:Date = new Date();
			return date.time + date.timezoneOffset * 60 * 1000;
		}
		
		private static function GENERATE_ID ():ByteArray
		{
			var ba:ByteArray = NEW_BYTE_ARRAY();
			while (ba.length < 8) ba.writeByte(int(Math.random() * 256));
			return ba;
		}
		
		private static function GENERATE_INSTALL_ID ():ByteArray
		{
			var ba:ByteArray = NEW_BYTE_ARRAY();
			var buf:ByteArray = mMD5.hash(mUniqueDeviceIdBuf);
			buf.position = 0;
			while (ba.length < 8) ba.writeByte(buf.readUnsignedByte());
			return ba;
		}
		
		private static function NEW_BYTE_ARRAY ():ByteArray
		{
			var ba:ByteArray = new ByteArray;
			ba.endian = Endian.LITTLE_ENDIAN;
			return ba;
		}
		
		
		//===============================================================================================
		//
		//																					Verification
		//
		//===============================================================================================
		
		
		private static function verify (data:ByteArray):Boolean
		{
			data.position = 0;
			
			try
			{
				log("============================================================");
				log("Header:");
				log("Package size: " + data.readUnsignedInt());
				log("Format: " + data.readShort());
				log("App ID: " + readUTF(data));
				log("App version: " + data.readUnsignedInt());
				log("Device ID: " + readUTF(data));
				var packLen:int = data.readShort();
				log("Number of packages: " + packLen);
				log("");
				
				for (var i:int = 0; i < packLen; ++i)
				{
					log("Package:");
					var type:int = data.readByte();
					log("Type: "+type);
					log("Format: "+data.readShort());
					
					var pack:Array = getPackageFromType(type);
					switch (pack)
					{
						case PACKAGE_INSTALL_UPDATE:
							log("Update ID: "+readDouble(data));
							log("Install ID: "+readDouble(data));
							break;
						
						case PACKAGE_START_SESSION:
						case PACKAGE_END_SESSION:
						case PACKAGE_EVENT:
							log("Update ID: "+readDouble(data));
							log("Session ID: "+readDouble(data));
							break;
						
						case PACKAGE_SPLITTER:
							log("Install ID: "+readDouble(data));
							break;
						
						case PACKAGE_PURCHASE:
							log("Purchase date: "+readDouble(data));
							log("Purchase date (local): "+readDouble(data));
							log("Install ID: "+readDouble(data));
							break;
						
						default:
							log("Error -> Unknown package type " + type);
							return false;
					}
					
					log("Pack ID: "+data.readUnsignedInt());
					switch (type)
					{
						case 0: // PACKAGE_INSTALL_UPDATE
							log("Install or update: "+data.readByte());
							log("Install date: "+readDouble(data));
							log("Install date (local): "+readDouble(data));
							log("Jailbreak: "+data.readByte());
							log("App version: "+data.readUnsignedInt());
							log("Platform: "+readUTF(data));
							log("Version: "+readUTF(data));
							log("Model: "+readUTF(data));
							log("Locale: "+readUTF(data));
							log("Store: "+readUTF(data));
							log("Referer: "+readUTF(data));
							break;
						
						case 1: // PACKAGE_START_SESSION
							log("Start session date: "+readDouble(data));
							log("Start session date (local): "+readDouble(data));
							break;
						
						case 2: // PACKAGE_END_SESSION
							log("Stop session date: "+readDouble(data));
							log("Stop session date (local): "+readDouble(data));
							log("Session duration: "+data.readUnsignedInt());
							break;
						
						case 3: // PACKAGE_SPLITTER
							log("Splitter name: "+readUTF(data));
							break;
						
						case 4: // PACKAGE_EVENT
							log("Event name: "+readUTF(data));
							log("Event date: "+readDouble(data));
							log("Event data (local): "+readDouble(data));
							log("App time: "+data.readUnsignedInt());
							var paramLen:int = data.readUnsignedInt();
							log("Number of parameters: "+paramLen);
							for (var j:int = 0; j < paramLen; j++)
							{
								log("Param name: "+readUTF(data));
								log("Param value: "+readDouble(data));
							}
							break;
						
						case 5: // PACKAGE_PURCHASE
							log("Ordinal number: "+data.readUnsignedInt());
							log("Price: "+data.readFloat());
							log("Price USD: "+data.readFloat());
							log("Purchases sum: "+data.readFloat());
							log("Platform: "+readUTF(data));
							log("Currency: "+readUTF(data));
							log("Internal purchase ID: "+readUTF(data));
							log("External purchase ID: "+readUTF(data));
							log("Transaction ID: "+readUTF(data));
							break;
					}
					log("");
				}
				log("============================================================");
				
				return true;
			} catch (error:Error)
			{
				log(error);
			}
			
			return false;
		}
		
		private static function readUTF (input:ByteArray):String
		{
			var buffer:ByteArray = NEW_BYTE_ARRAY();
			var len:int = input.length;
			while (input.bytesAvailable)
			{
				var byte:int = input.readByte();
				if (byte != 0) buffer.writeByte(byte);
				else break;
			}
			buffer.position = 0;
			return buffer.readUTFBytes(buffer.length);
		}
		
		private static function readDouble (input:ByteArray):String
		{
			var str:String = "";
			var i:int = 0;
			while (i++ < 8)
				str += input.readUnsignedByte().toString("16") + " ";
			return str;
		}
		
		private static function getPackageFromType (type:int):Array
		{
			switch (type)
			{
				case PACKAGE_INSTALL_UPDATE[0]:	return PACKAGE_INSTALL_UPDATE;
				case PACKAGE_START_SESSION[0]: 	return PACKAGE_START_SESSION;
				case PACKAGE_END_SESSION[0]:		return PACKAGE_END_SESSION;
				case PACKAGE_SPLITTER[0]:				return PACKAGE_SPLITTER;
				case PACKAGE_EVENT[0]:					return PACKAGE_EVENT;
				case PACKAGE_PURCHASE[0]:				return PACKAGE_PURCHASE;
			}
			return null;
		}
		
		private static function log (...params):void
		{
			const TAG:String = '[AbsStat] ';
			trace(TAG + params.join(', '));
		}
	}
}