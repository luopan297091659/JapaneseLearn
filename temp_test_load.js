try {
  require('./src/controllers/studyPlanController');
  console.log('LOAD_OK');
} catch(e) {
  console.log('LOAD_FAIL', e.code, e.message.split('\n')[0]);
}
