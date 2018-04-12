package fairygui {
	import fairygui.AssetProxy;
	import fairygui.DisplayListItem;
	import fairygui.PackageItem;
	import fairygui.PackageItemType;
	import fairygui.display.BMGlyph;
	import fairygui.display.BitmapFont;
	import fairygui.display.Frame;
	import fairygui.utils.PixelHitTestData;
	import fairygui.utils.ToolSet;
	
	import fairyguiExternal.custom.packinfo.PackData;
	import fairyguiExternal.custom.utils.PackUtils;
	
	import game.data.CompressionManager;
	import game.utils.ByteArray;
	
	import laya.maths.Rectangle;
	import laya.resource.Texture;
	import laya.utils.Byte;
	import laya.utils.Utils;
	
	public class UIPackage {
		private var _id: String;
		private var _name: String;
		private var _basePath: String;
		private var _items: Vector.<PackageItem>;
		private var _itemsById: Object;
		private var _itemsByName: Object;
		private var _resKey: String;
		private var _resData: Object;
		private var _customId: String;
		private var _sprites: Object;
		private var _hitTestDatas:Object;
		
		//internal
		public static var _constructing: Number = 0;
		
		private static var _packageInstById: Object = {};
		private static var _packageInstByName: Object = {};
		private static var _bitmapFonts: Object = {};
		private static var _stringsSource: Object = null;
		
		private static const sep0: String = ",";
		private static const sep1: String = "\n";
		private static const sep2: String = " ";
		private static const sep3: String = "=";
		
		public function UIPackage() {
			this._items = new Vector.<PackageItem>();
			this._sprites = {};
			this._hitTestDatas = {};
		}
		
		public static function getById(id: String): UIPackage {
			return UIPackage._packageInstById[id];
		}
		
		public static function getByName(name: String): UIPackage {
			return UIPackage._packageInstByName[name];
		}
		
		public static function addPackage(resKey: String, descData:ArrayBuffer = null): UIPackage {
			var pkg: UIPackage = new UIPackage();
			pkg.create(resKey, descData);
			UIPackage._packageInstById[pkg.id] = pkg;
			UIPackage._packageInstByName[pkg.name] = pkg;
			pkg.customId = resKey;
			return pkg;
		}
		
		public static function removePackage(packageIdOrName: String): void {
			var pkg: UIPackage = UIPackage._packageInstById[packageIdOrName];
			if(!pkg)
				pkg = UIPackage._packageInstByName[packageIdOrName];
			if(!pkg)
				throw new Error("unknown package: " + packageIdOrName);

			pkg.dispose();
			delete UIPackage._packageInstById[pkg.id];
			if(pkg._customId != null)
				delete UIPackage._packageInstById[pkg._customId];
			delete UIPackage._packageInstByName[pkg.name];
		}
		
		public static function createObject(pkgName: String,resName: String,userClass:Object = null): GObject {
			var pkg: UIPackage = UIPackage.getByName(pkgName);
			if(pkg)
				return pkg.createObject(resName,userClass);
			else
				return null;
		}
		
		public static function createObjectFromURL(url: String,userClass:Object = null): GObject {
			var pi: PackageItem = UIPackage.getItemByURL(url);
			if(pi)
				return pi.owner.internalCreateObject(pi,userClass);
			else
				return null;
		}
		
		public static function getItemURL(pkgName: String,resName: String): String {
			var pkg: UIPackage = UIPackage.getByName(pkgName);
			if(!pkg)
				return null;
			
			var pi: PackageItem = pkg._itemsByName[resName];
			if(!pi)
				return null;
			
			return "ui://" + pkg.id + pi.id;
		}
		
		public static function getItemByURL(url: String): PackageItem {
			var pos1:int = url.indexOf("//");
			if (pos1 == -1)
				return null;
			
			var pos2:int = url.indexOf("/", pos1 + 2);
			if (pos2 == -1)
			{
				if (url.length > 13)
				{
					var pkgId:String = url.substr(5, 8);
					var pkg:UIPackage = getById(pkgId);
					if (pkg != null)
					{
						var srcId:String = url.substr(13);
						return pkg.getItemById(srcId);
					}
				}
			}
			else
			{
				var pkgName:String = url.substr(pos1 + 2, pos2 - pos1 - 2);
				pkg = getByName(pkgName);
				if (pkg != null)
				{
					var srcName:String = url.substr(pos2 + 1);
					return pkg.getItemByName(srcName);
				}
			}
			
			return null;
		}
		
		public static function normalizeURL(url:String):String
		{
			if(url==null)
				return null;
			
			var pos1:int = url.indexOf("//");
			if (pos1 == -1)
				return null;
			
			var pos2:int = url.indexOf("/", pos1 + 2);
			if (pos2 == -1)
				return url;
			
			var pkgName:String = url.substr(pos1 + 2, pos2 - pos1 - 2);
			var srcName:String = url.substr(pos2 + 1);
			return getItemURL(pkgName, srcName);
		}
		
		public static function getBitmapFontByURL(url: String): BitmapFont {
			return UIPackage._bitmapFonts[url];
		}
		
		public static function setStringsSource(source:String):void	{
			UIPackage._stringsSource = {};
			var resources:Object = PackUtils.findChildNode(new PackData(source),"resources");
			var packData:PackData = new PackData(resources);
			var cInfo:Object;
			for(var cType:String in packData.jsonInfo) {
				if(cType == "string") {
					cInfo = packData.jsonInfo[cType];
					if(cInfo==""||!cInfo)
						continue;
					var key:String = cInfo.getAttribute("name");
					var text:String = cInfo.textContent;
					var i:int = key.indexOf("-");
					if(i==-1)
						continue;
					
					var key2:String = key.substr(0, i);
					var key3:String = key.substr(i+1);
					var col:Object = UIPackage._stringsSource[key2];
					if(!col) {
						col = {};
						UIPackage._stringsSource[key2] = col;
					}
					col[key3] = text;
				}
			}
		}
		
		private function create(resKey: String, descData:ArrayBuffer): void {
			this._resKey = resKey;
			
			this.loadPackage(descData);
		}
		
		private function loadPackage(descData:ArrayBuffer): void {
			var str: String;
			var arr: Array;
			
			if(!descData)
				descData = AssetProxy.inst.getRes(this._resKey+".fui");
			
			this.decompressPackage(descData);
			
			str = this.getDesc("sprites.bytes");
			
			arr = str.split(UIPackage.sep1);
			var cnt: Number = arr.length;
			for(var i: Number = 1;i < cnt;i++) {
				str = arr[i];
				if(!str)
					continue;
				
				var arr2: Array = str.split(UIPackage.sep2);
				
				var sprite: AtlasSprite = new AtlasSprite();
				var itemId: String = arr2[0];
				var binIndex: Number = parseInt(arr2[1]);
				if(binIndex >= 0)
					sprite.atlas = "atlas" + binIndex;
				else {
					var pos: Number = itemId.indexOf("_");
					if(pos == -1)
						sprite.atlas = "atlas_" + itemId;
					else
						sprite.atlas = "atlas_" + itemId.substr(0,pos);
				}
				
				sprite.rect.x = parseInt(arr2[2]);
				sprite.rect.y = parseInt(arr2[3]);
				sprite.rect.width = parseInt(arr2[4]);
				sprite.rect.height = parseInt(arr2[5]);
				sprite.rotated = arr2[6] == "1";
				this._sprites[itemId] = sprite;
			}
			
			str = this.getDesc("hittest.bytes");
			if(str!=null)
			{
				var ba:Byte =ToolSet.base64Decode(str);
				ba.endian = Byte.BIG_ENDIAN;
				while(ba.bytesAvailable)
				{
					var hitTestData:PixelHitTestData = new PixelHitTestData();
					_hitTestDatas[ba.readUTFString()] = hitTestData;
					hitTestData.load(ba);
				}
			}
			
			str = this.getDesc("package.xml");
			var rootNode:Object = str;
			this._id = rootNode.id;
			this._name = rootNode.name;
			var resources: Array =rootNode.resources;
			this._itemsById = {};
			this._itemsByName = {};
			var pi: PackageItem;
			var cxml: Object;
			
			for(var cType:String in resources) {
				var cInfo:Object = resources[cType];
				var proType:String = PackUtils.getTypeof(cInfo);
				if(proType != "array") cInfo = [cInfo];
				for each(cxml in cInfo) {
					pi = new PackageItem();
					pi.owner = this;
					pi.type = PackageItemType.parse(cType);
					pi.id = cxml.id;
					pi.name = cxml.name;
					pi.file = cxml.file;
					str = cxml.size;
					if(str) {
						arr = str.split(UIPackage.sep0);
						pi.width = parseInt(arr[0]);
						pi.height = parseInt(arr[1]);
					}
					switch(pi.type) {
						case PackageItemType.Image:
							str = cxml.scale;
							if(str == "9grid") {
								pi.scale9Grid = new laya.maths.Rectangle();
								str = cxml.scale9grid;
								if(str) {
									pi.tileGridIndice = parseInt(str);
									arr = str.split(UIPackage.sep0);
									pi.scale9Grid.x = parseInt(arr[0]);
									pi.scale9Grid.y = parseInt(arr[1]);
									pi.scale9Grid.width = parseInt(arr[2]);
									pi.scale9Grid.height = parseInt(arr[3]);
									
									str = cxml.gridTile;
									if(str)
										pi.tileGridIndice = parseInt(str);
								}
							}
							else if(str == "tile") {
								pi.scaleByTile = true;
							}
							str = cxml.smoothing;
							pi.smoothing = str != "false";
							break;
						case PackageItemType.Component:
							UIObjectFactory.resolvePackageItemExtension(pi);
							break;
					}
					this._items.push(pi);
					this._itemsById[pi.id] = pi;
					if(pi.name != null)
						this._itemsByName[pi.name] = pi;
				}
			}
			
			cnt = this._items.length;
			for(i = 0;i < cnt;i++) {
				pi = this._items[i];
				if(pi.type == PackageItemType.Font) {
					this.loadFont(pi);
					UIPackage._bitmapFonts[pi.bitmapFont.id] = pi.bitmapFont;
				}
			}
		}
		
		private function decompressPackage(buf: ArrayBuffer): void {
			this._resData = {};
			
			var mark:Uint8Array = new Uint8Array(buf.slice(0,2));
			if(mark[0]==0x50 && mark[1]==0x4b)
			{
				buf.position = 0;
				decodeUncompressed(buf);
			}
			else
			{
				var data: Uint8Array = CompressionManager.decodeZlib(buf);
				
				var info:ByteArray = new ByteArray();
				info.writeArrayBuffer(data);
				info.position = 0;
				var num:int = info.readInt();
				var fileNameLen:int;
				var fileName:String;
				var fileInfo:Object;
				var fileType:int;
				while(num>0)
				{
					fileNameLen = info.readByte();
					fileName = info.readUTFBytes(fileNameLen);
					fileType = info.readByte();
					if(fileType == 1)
					{
						fileInfo =  info.readObject();
					}else
					{
						var byteLen:int = info.readInt();
						var bytes:ByteArray = new ByteArray();
						info.readBytes(bytes,0,byteLen);
						fileInfo = String(bytes);
					}
					this._resData[fileName] = fileInfo;
					num--;
				}
			}
			var spLen:int = info.readInt();
			var sp:String =  info.readUTFBytes(spLen);
			this._resData["sprites.bytes"] =sp;
		}
		
		private function decodeUncompressed(buf: ArrayBuffer):void {
			var ba:Byte = new Byte(buf);			
			var pos:int = ba.length - 22;
			ba.pos = pos + 10;
			var entryCount:int = ba.getUint16();
			ba.pos = pos + 16;
			pos = ba.getInt32();
			
			for (var i:int = 0; i < entryCount; i++)
			{
				ba.pos = pos + 28;
				var len:int = ba.getUint16();
				var len2:int = ba.getUint16() + ba.getUint16();
				
				ba.pos = pos + 46;
				var entryName:String = ba.getUTFBytes(len);
				
				if (entryName[entryName.length - 1] != '/' && entryName[entryName.length - 1] != '\\') //not directory
				{
					ba.pos = pos + 20;
					var size:int = ba.getInt32();
					ba.pos  = pos + 42;
					var offset:int = ba.getInt32() + 30 + len;
					
					if (size > 0)
					{
						ba.pos = offset;
						this._resData[entryName] = ba.readUTFBytes(size);
					}
				}
				
				pos += 46 + len + len2;
			}
		}
		
		public function dispose(): void {
			var cnt:Number=this._items.length;
			for(var i: Number = 0;i < cnt;i++) {
				var pi: PackageItem = this._items[i];
				if(pi.type==PackageItemType.Atlas)
				{
					var texture: Texture = pi.texture;
					if(texture != null)
						texture.destroy(true);
				}
				
				if(pi.bitmapFont != null) {
					delete UIPackage._bitmapFonts[pi.bitmapFont.id];
				}
			}
		}
		
		public function get id(): String {
			return this._id;
		}
		
		public function get name(): String {
			return this._name;
		}
		
		public function get customId(): String {
			return this._customId;
		}
		
		public function set customId(value: String):void {
			if (this._customId != null)
				delete UIPackage._packageInstById[this._customId];
			this._customId = value;
			if (this._customId != null)
				UIPackage._packageInstById[this._customId] = this;
		}
		
		public function createObject(resName: String, userClass: Object = null): GObject {
			var pi: PackageItem = this._itemsByName[resName];
			if (pi)
				return this.internalCreateObject(pi, userClass);
			else
				return null;
		}
		
		public function internalCreateObject(item: PackageItem, userClass: Object = null): GObject {
			var g: GObject;
			if (item.type == PackageItemType.Component) {
				if (userClass != null)
					g = new userClass();
				else
					g = UIObjectFactory.newObject(item);
			}
			else
				g = UIObjectFactory.newObject(item);
			
			if (g == null)
				return null;
			
			UIPackage._constructing++;
			g.packageItem = item;
			g.constructFromResource();
			UIPackage._constructing--;
			return g;
		}
		
		public function getItemById(itemId: String): PackageItem {
			return this._itemsById[itemId];
		}
		
		public function getItemByName(resName: String): PackageItem {
			return this._itemsByName[resName];
		}
		
		public function getItemAssetByName(resName: String): Object {
			var pi: PackageItem = this._itemsByName[resName];
			if (pi == null) {
				throw "Resource not found -" + resName;
			}
			
			return this.getItemAsset(pi);
		}
		
		public function getItemAssetURL(item: PackageItem):String {
			return this._resKey + "@" + item.file;;
		}
		
		public function getItemAsset(item: PackageItem): Object {
			switch (item.type) {
				case PackageItemType.Image:
					if (!item.decoded) {
						item.decoded = true;
						var sprite: AtlasSprite = this._sprites[item.id];
						if (sprite != null)
							item.texture = this.createSpriteTexture(sprite);
					}
					return item.texture;
					
				case PackageItemType.Atlas:
					if (!item.decoded) {
						item.decoded = true;
						var fileName:String = (item.file != null && item.file.length > 0) ? item.file : (item.id + ".png");
						item.texture = AssetProxy.inst.getRes(this._resKey + "@" + fileName);
						if(!fairygui.UIConfig.textureLinearSampling)
							item.texture.isLinearSampling = false;
					}
					return item.texture;
					
				case PackageItemType.Sound:
					if (!item.decoded) {
						item.decoded = true;
						item.sound = AssetProxy.inst.getRes(this._resKey + "@" + item.file);
					}
					return item.sound;
					
				case PackageItemType.Font:
					if (!item.decoded) {
						item.decoded = true;
						this.loadFont(item);
					}
					return item.bitmapFont;
					
				case PackageItemType.MovieClip:
					if (!item.decoded) {
						item.decoded = true;
						this.loadMovieClip(item);
					}
					return item.frames;
					
				case PackageItemType.Component:
					if (!item.decoded) {
						item.decoded = true;
						var str: String = this.getDesc(item.id + ".xml");
						item.componentData = new PackData(str);
						
						loadComponentChildren(item);
						item.displayList.sort(sortDisList);
						translateComponent(item);
					}
					return item.componentData;
					
				default:
					return AssetProxy.inst.getRes(this._resKey + "@" + item.id);
			}
		}
		
		private function sortDisList($value1:DisplayListItem,$value2:DisplayListItem):int
		{
			var fir:int = $value1.desc.getAttribute("sortNum");
			var sec:int = $value2.desc.getAttribute("sortNum");
			if(fir > sec)
			{
				return 1;
			}
			if(fir  < sec)
			{
				return -1;
			}
			return 0;
		}
		
		private function getDesc(fn:String):String {
			return this._resData[fn];
		}
		
		public function getPixelHitTestData(itemId:String):PixelHitTestData
		{
			return _hitTestDatas[itemId];
		}
		
		private function loadComponentChildren(item:PackageItem):void
		{
			var listNode:Object = item.componentData.jsonInfo.displayList;
			if (listNode != null)
			{
				var cInfo:Object;
				var packData:PackData;
				var proType:String;
				item.displayList = new Vector.<DisplayListItem>();
				var di:DisplayListItem;
				var i:int=0;
				var tagName:String;
				var src:String;
				var pkg:UIPackage;
				var pkgId:String;
				var pi:PackageItem;
				for(var dType:String in listNode)
				{
					cInfo = listNode[dType];
					proType = PackUtils.getTypeof(cInfo);
					if(proType != "array") cInfo = [cInfo];
					for each(var cObj:Object in cInfo)
					{
						packData = new PackData(cObj);
						tagName = dType;
						src = packData.getAttribute("src");
						if (src)
						{
							pkgId = packData.getAttribute("pkg");
							if (pkgId && pkgId != item.owner.id)
								pkg = UIPackage.getById(pkgId);
							else
								pkg = item.owner;
							
							pi = pkg != null ? pkg.getItemById(src) : null;
							if (pi != null)
								di = new DisplayListItem(pi, null);
							else
								di = new DisplayListItem(null, tagName);
						}
						else
						{
							if (tagName == "text" && packData.getAttribute("input")=="true")
								di = new DisplayListItem(null, "inputtext");
							else
								di = new DisplayListItem(null, tagName);
						}
						di.desc = packData;
						item.displayList[i] = di;
						i++;
					}
				}
			}
			else
				item.displayList =new Vector.<DisplayListItem>(0);
		}
		
		private function translateComponent(item:PackageItem):void {
			if(UIPackage._stringsSource==null)
				return;
			
			var strings:Object = UIPackage._stringsSource[this.id + item.id];
			if(strings==null)
				return;
			
			var length1: Number = item.displayList.length;
			var length2: Number;
			var value:*;
			var cxml:Object, dxml:Object, exml:Object;
			var ename:String;
			var elementId:String;
			var items:Array;
			var i1:Number, i2:Number, j:Number;
			var str:String;
			
			var cInfo:Object;
			var cType:String
			for (i1 = 0; i1 < length1; i1++) {
				cxml = item.displayList[i1].desc;
				ename = cxml.nodeName;
				elementId = cxml.getAttribute("id");
				
				str = cxml.getAttribute("tooltips");
				if(str)	{
					value = strings[elementId+"-tips"];
					if(value!=undefined)
						cxml.setAttribute("tooltips", value);
				}
				
				dxml = PackUtils.findChildNode(cxml, "gearText");
				if(dxml) {
					dxml =  new PackData(dxml);
					value = strings[elementId+"-texts"];
					if(value!=undefined)
						dxml.setAttribute("values", value);
					
					value = strings[elementId+"-texts_def"];
					if(value!=undefined)
						dxml.setAttribute("default", value);
				}
				
				if(ename=="text" || ename=="richtext")	{
					value = strings[elementId];
					if(value!=undefined)
						cxml.setAttribute("text", value);
					value = strings[elementId+"-prompt"];
					if(value!=undefined)
						cxml.setAttribute("prompt", value);
				}
				else if(ename=="list")	{
					for(cType in cxml.jsonInfo) {
						if(cType == "item") {
							cInfo = cxml.jsonInfo[cType];
							if(cInfo==""||!cInfo)
								continue;
							value = strings[elementId+"-"+j];
							if(value!=undefined)
								cInfo.setAttribute("title", value);
						}
					}
				}
				else if(ename=="component")	{
					dxml = PackUtils.findChildNode(cxml, "Button");
					if(dxml) {
						dxml = new PackData(dxml);
						value = strings[elementId];
						if(value!=undefined)
							dxml.setAttribute("title", value);
						value = strings[elementId+"-0"];
						if(value!=undefined)
							dxml.setAttribute("selectedTitle", value);
						continue;
					}
					
					dxml = PackUtils.findChildNode(cxml, "Label");
					if(dxml) {
						dxml = new PackData(dxml);
						value = strings[elementId];
						if(value!=undefined)
							dxml.setAttribute("title", value);
						value = strings[elementId+"-prompt"];
						if(value!=undefined)
							dxml.setAttribute("prompt", value);
						continue;
					}
					
					dxml =  PackUtils.findChildNode(cxml, "ComboBox");
					if(dxml) {
						dxml = new PackData(dxml);
						value = strings[elementId];
						if(value!=undefined)
							dxml.setAttribute("title", value);
						
						for(cType in dxml.jsonInfo) {
							if(cType == "item") {
								cInfo = dxml.jsonInfo[cType];
								if(cInfo==""||!cInfo)
									continue;
								value = strings[elementId+"-"+j];
								if(value!=undefined)
									cInfo.setAttribute("title", value);
							}
						}
						continue;
					}
				}
			}
		}
		
		private function createSpriteTexture(sprite: AtlasSprite): Texture {
			var atlasItem: PackageItem = this._itemsById[sprite.atlas];
			if (atlasItem != null) {
				var atlasTexture:Texture = Texture(this.getItemAsset(atlasItem));
				if(atlasTexture == null)
					return null;
				else
					return this.createSubTexture(atlasTexture,sprite.rect);
			}
			else
				return null;
		}
		
		private function createSubTexture(atlasTexture: Texture, clipRect: Rectangle): Texture {
			var texture: Texture = Texture.createFromTexture(atlasTexture, 
				clipRect.x, clipRect.y, clipRect.width, clipRect.height);
			return texture;
		}
		
		private function loadMovieClip(item: PackageItem): void {
			var xml: Object = Utils.parseXMLFromString(this.getDesc(item.id + ".xml")).firstChild;
			var str: String;
			var arr:Array;
			
			str = xml.getAttribute("interval");
			if (str)
				item.interval = parseInt(str);
			str = xml.getAttribute("swing");
			if (str)
				item.swing = str == "true";
			str = xml.getAttribute("repeatDelay");
			if (str)
				item.repeatDelay = parseInt(str);
			
			var frameCount: Number = parseInt(xml.getAttribute("frameCount"));
			item.frames = new Array();
			var frameNodes: Array = ToolSet.findChildNode(xml, "frames").childNodes;
			var i:Number = 0;
			var len:Number = frameNodes.length;
			for(var k: Number = 0;k < len;k++) {
				var frameNode: Object = frameNodes[k];
				if(frameNode.nodeName!="frame")
					continue;
				
				var frame: Frame = new Frame();
				str = frameNode.getAttribute("rect");
				arr = str.split(UIPackage.sep0);
				frame.rect = new Rectangle(parseInt(arr[0]),parseInt(arr[1]),parseInt(arr[2]),parseInt(arr[3]));
				str = frameNode.getAttribute("addDelay");
				if(str)
					frame.addDelay = parseInt(str);
				item.frames[i] = frame;
				
				if (frame.rect.width == 0)
					continue;
				
				str = frameNode.getAttribute("sprite");
				if (str)
					str = item.id + "_" + str;
				else				
					str = item.id + "_" + i;
				
				var sprite: AtlasSprite = this._sprites[str];
				if(sprite != null)
					frame.texture = this.createSpriteTexture(sprite);
				
				i++;
			}
		}
		
		private function loadFont(item: PackageItem): void {
			var font: BitmapFont = new BitmapFont();
			font.id = "ui://" + this.id + item.id;
			var str: String = this.getDesc(item.id + ".fnt");
			
			var lines: Array = str.split(UIPackage.sep1);
			var lineCount: Number = lines.length;
			var i: Number = 0;
			var kv: Object = {};
			var ttf: Boolean = false;
			var size: Number = 0;
			var xadvance: Number = 0;
			var resizable: Boolean = false;
			var atlasOffsetX: Number = 0, atlasOffsetY: Number = 0;
			var charImg: PackageItem;
			var mainTexture: Texture;
			var lineHeight:int = 0;
			
			for (i = 0; i < lineCount; i++) {
				str = lines[i];
				if (str.length == 0)
					continue;
				
				str = ToolSet.trim(str);
				var arr: Array = str.split(UIPackage.sep2);
				for (var j: Number = 1; j < arr.length; j++) {
					var arr2: Array = arr[j].split(UIPackage.sep3);
					kv[arr2[0]] = arr2[1];
				}
				
				str = arr[0];
				if (str == "char") {
					var bg: BMGlyph = new BMGlyph();
					bg.x = isNaN(kv.x) ? 0 : parseInt(kv.x);
					bg.y = isNaN(kv.y) ? 0 : parseInt(kv.y);
					bg.offsetX = isNaN(kv.xoffset) ? 0 : parseInt(kv.xoffset);
					bg.offsetY = isNaN(kv.yoffset) ? 0 : parseInt(kv.yoffset);
					bg.width = isNaN(kv.width) ? 0 : parseInt(kv.width);
					bg.height = isNaN(kv.height) ? 0 : parseInt(kv.height);
					bg.advance = isNaN(kv.xadvance) ? 0 : parseInt(kv.xadvance);
					if (kv.chnl != undefined) {
						bg.channel = parseInt(kv.chnl);
						if (bg.channel == 15)
							bg.channel = 4;
						else if (bg.channel == 1)
							bg.channel = 3;
						else if (bg.channel == 2)
							bg.channel = 2;
						else
							bg.channel = 1;
					}
					
					if (!ttf) {
						if (kv.img) {
							charImg = this._itemsById[kv.img];
							if (charImg != null) {
								charImg.load();
								bg.width = charImg.width;
								bg.height = charImg.height;
								bg.texture = charImg.texture;
							}
						}
					}
					else if (mainTexture != null) {
						bg.texture = this.createSubTexture(mainTexture, new Rectangle(bg.x + atlasOffsetX, bg.y + atlasOffsetY, bg.width, bg.height));
					}
					
					if (ttf)
						bg.lineHeight = lineHeight;
					else {
						if(bg.advance == 0) {
							if(xadvance == 0)
								bg.advance = bg.offsetX + bg.width;
							else
								bg.advance = xadvance;
						}
						
						bg.lineHeight = bg.offsetY < 0 ? bg.height : (bg.offsetY + bg.height);
						if(size>0 && bg.lineHeight<size)
							bg.lineHeight = size;
					}
					font.glyphs[String.fromCharCode(kv.id)] = bg;
				}
				else if (str == "info") {
					ttf = kv.face != null;
					if(!isNaN(kv.size))
						size = parseInt(kv.size);
					resizable = kv.resizable == "true";
					if (ttf) {
						var sprite: AtlasSprite = this._sprites[item.id];
						if (sprite != null) {
							atlasOffsetX = sprite.rect.x;
							atlasOffsetY = sprite.rect.y;
							var atlasItem: PackageItem = this._itemsById[sprite.atlas];
							if(atlasItem != null)
								mainTexture = Texture(this.getItemAsset(atlasItem));
						}
					}
				}
				else if (str == "common") {
					if(!isNaN(kv.lineHeight))
						lineHeight = parseInt(kv.lineHeight);
					if(size==0)
						size = lineHeight;
					else if(lineHeight==0)
						lineHeight = size;
					if(!isNaN(kv.xadvance))
						xadvance = parseInt(kv.xadvance);
				}
			}
			
			if (size == 0 && bg)
				size = bg.height;
			
			font.ttf = ttf;
			font.size = size;
			font.resizable = resizable;
			item.bitmapFont = font;
		}
	}
}
import laya.maths.Rectangle;

class AtlasSprite {
	public function AtlasSprite() {
		this.rect = new Rectangle();
	}
	
	public var atlas: String;
	public var rect: Rectangle;
	public var rotated: Boolean;
}