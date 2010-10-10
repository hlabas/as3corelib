/*
Copyright (c) 2008, Adobe Systems Incorporated
All rights reserved.

Redistribution and use in source and binary forms, with or without 
modification, are permitted provided that the following conditions are
met:

* Redistributions of source code must retain the above copyright notice, 
this list of conditions and the following disclaimer.

* Redistributions in binary form must reproduce the above copyright
notice, this list of conditions and the following disclaimer in the 
documentation and/or other materials provided with the distribution.

* Neither the name of Adobe Systems Incorporated nor the names of its 
contributors may be used to endorse or promote products derived from 
this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS
IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO,
THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR 
CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
*/

package com.adobe.air.logging
{
	import flash.filesystem.File;
	
	import mx.collections.ArrayCollection;
	import mx.collections.Sort;
	import mx.formatters.DateFormatter;
	import mx.utils.ObjectUtil;
	
	
	/**
	 * This logging target provides a log file backup creation system based on two policies:
	 *  <ol>
	 *    <li>Date based (@see rollingInterval)</li>
	 *    <li>Size based (@see maxLogFileWeight)</li>
	 *  </ol>
	 * 
	 * This class will only work when running within Adobe AIR>
	 * 
	 * @author Hervé Labas - La Fabrick Interactive - herve.labas@lafabrick.com
	 */	
	public class RollingFileTarget extends FileTarget
	{	
		/**
		 * Disables the date based rolling 
		 */		
		public static const NO_INTERVAL:uint = 1;
		/**
		 * Enables an every day rolling behavior 
		 */
		public static const DAY_INTERVAL:uint = 6;
		/**
		 * Enables an every month rolling behavior 
		 */
		public static const MONTH_INTERVAL:uint = 4;
		/**
		 * Enables an every hour rolling behavior 
		 */
		public static const YEAR_INTERVAL:uint = 2;
		
		/**
		 * Defines the time interval between each log file roll.
		 * Defaults to DAY_INTERVAL
		 * @see rollingRequiredByDate 
		 * @see rollLogFileByDate 
		 */		
		public var rollingInterval:uint = DAY_INTERVAL;
		
		/**
		 * Maximum weight of a log file in bytes.
		 * Defaults to approx 1Mb
		 * @see rollingRequiredBySize
		 */		
		public var maxLogFileWeight:Number = 1000000;
		
		/**
		 * Returns the maximum backup files before deleting them
		 * @see handleBackupRemoval
		 */		
		public var maxLogBackups:Number = 5;
		
		/**
		 * FIFO containing backup files to handle backup removals (date policy)
		 */	
		protected var _dateBackupList:Array = new Array();
		/**
		 * FIFO containing backup files to handle backup removals (size policy) 
		 */	 
		protected var _sizeBackupList:Array = new Array(); 
		
		public function RollingFileTarget(logFile:File = null)
		{
			super(logFile);
			initFifos();
		}
		
		protected function initFifos():void
		{
			if (!log || !log.parent || !log.parent.isDirectory)
			{
				return;
			}
			
			var sortedList:ArrayCollection = new ArrayCollection(log.parent.getDirectoryListing());
			sortedList.sort = new Sort();
			sortedList.sort.compareFunction = function (f1:File, f2:File, fields:Array = null):int
			{
				return ObjectUtil.dateCompare(f1.modificationDate, f2.modificationDate);
			}
			sortedList.refresh();
			
			for each (var potentialLogFile:File in sortedList)
			{
				var matchSize:String = "^" + log.name + "\.[0-9]+";
				var matchDate:String = "^[0-9]{4}-[0-9]{2}-[0-9]{2}-" + log.name + "$";
				if (potentialLogFile.name.match(matchDate))
				{
					_dateBackupList.push(potentialLogFile);
				}
				if (potentialLogFile.name.match(matchSize))
				{
					_sizeBackupList.push(potentialLogFile);
				}
			}
		}
		
		override protected function write(msg:String):void
		{
			if (rollingRequiredByDate)
			{
				rollLogFileByDate();
			}
			if (rollingRequiredBySize)
			{
				rollLogFileBySize();
			}
			super.write(msg);
		}
		
		/**
		 * Creates a backup file using rolling interval configuration
		 */		
		protected function rollLogFileByDate():void
		{
			// Use date to determine the backup file name
			var df:DateFormatter = new DateFormatter();
			df.formatString = "YYYY-MM-DD";
			var today:Date = new Date();
			switch (rollingInterval)
			{
				case DAY_INTERVAL:
					today.date--;
					break;
				case MONTH_INTERVAL:
					today.month--;
					break;
				case YEAR_INTERVAL:
					today.year--;
					break;
			}
			
			// Create backup of current log file
			var backupFileName:String = log.parent.nativePath + File.separator + df.format(today) + "-" + log.name;
			var backupFile:File = new File(backupFileName);
			log.copyTo(backupFile, true);
			
			// Store backup in fifo for further removal
			_dateBackupList.push(backupFile);
			
			// Clean the log now we have a backup
			clear();
			
			// Speaks for itself 
			handleBackupRemoval(_dateBackupList);
		}
		
		/**
		 * Takes care of removing backup log files if neccessary
		 */		
		protected function handleBackupRemoval(fifo:Array):void
		{
			try
			{
				if (fifo.length > maxLogBackups)
				{
					var toRemove:File = fifo.shift();
					toRemove.deleteFile();
				}
			}
			catch (e:Error)
			{
				trace("Couldn't delete backup log file");
			}
		}	
		
		/**
		 * Tells wether a file roll must be done
		 * @return true if a backup must be created, false otherwise
		 */	
		protected function get rollingRequiredByDate():Boolean
		{
			if (!log.exists || rollingInterval == NO_INTERVAL)
			{
				return false;
			}
			var df:DateFormatter = new DateFormatter();
			df.formatString = "YYMMDD";
			var logModificationDate:String = df.format(log.modificationDate);
			var today:String = df.format(new Date());
			var logModificationCmp:Number = Number(logModificationDate.substr(0,rollingInterval));
			var todayCmp:Number = Number(today.substr(0,rollingInterval));
			return (todayCmp > logModificationCmp);
		}
		
		/**
		 * Creates a backup file when the current log file's size reached its size limit
		 */	
		protected function rollLogFileBySize():void
		{
			var index:Number = 1;
			while (index != 0)
			{
				var backupFileName:String = log.parent.nativePath + File.separator + log.name + "." + index;
				var backupFile:File = new File(backupFileName);
				if (backupFile.exists)
				{
					index++;
				}
				else
				{
					log.copyTo(backupFile, true);
					clear();
					_sizeBackupList.push(backupFile);
					handleBackupRemoval(_sizeBackupList);
					index = 0;
				}
			}
		}
		
		/**
		 * Tells whether a backup file should be created by checking the file size 
		 * @return true if a backup file must be created, false otherwise
		 */		
		protected function get rollingRequiredBySize():Boolean
		{
			if (!log.exists || maxLogFileWeight == 0)
			{
				return false;
			}
			return (log.size > maxLogFileWeight);
		}
	}
}