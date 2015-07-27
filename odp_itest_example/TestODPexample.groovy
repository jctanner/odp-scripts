/**
 * Licensed to the Apache Software Foundation (ASF) under one
 * or more contributor license agreements.  See the NOTICE file
 * distributed with this work for additional information
 * regarding copyright ownership.  The ASF licenses this file
 * to you under the Apache License, Version 2.0 (the
 * "License"); you may not use this file except in compliance
 * with the License.  You may obtain a copy of the License at
 * <p/>
 * http://www.apache.org/licenses/LICENSE-2.0
 * <p/>
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

package org.apache.bigtop.itest.odp

import org.junit.BeforeClass
import org.junit.AfterClass
import static org.junit.Assert.assertNotNull
import org.apache.bigtop.itest.shell.Shell
import static org.junit.Assert.assertTrue
import org.junit.Test
import org.apache.hadoop.conf.Configuration
import org.apache.bigtop.itest.JarContent
import org.apache.bigtop.itest.TestUtils
import org.apache.commons.logging.LogFactory
import org.apache.commons.logging.Log

//import org.junit.runner.RunWith

class TestODPsmoke {
  static private Log LOG = LogFactory.getLog(Object.class);
  static Shell sh = new Shell("/bin/bash -s");

  @AfterClass
  public static void tearDown() {
  }

  @BeforeClass
  static void setUp() {
  }

  @Test
  void testWhoami() {
    sh.exec("whoami");
    assertTrue("whoami failed. " + sh.getOut() + " " + sh.getErr(), sh.getRet() == 0);
  }

  @Test
  void testWhoami2() {
    sh.exec("whoami");
    assertTrue("whoami failed. " + sh.getOut() + " " + sh.getErr(), sh.getRet() == 0);
  }

}
